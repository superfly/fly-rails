require 'fly.io-rails/machines'
require 'fly.io-rails/hcl'
require 'fly.io-rails/actions'
require 'toml'
require 'json'

config = File.expand_path('config/fly.rb', Rails.application.root)
if File.exist? config
  @config = Fly::DSL::Config.new
  @config.instance_eval IO.read(config), config
end

namespace :fly do
  desc 'Deploy fly application'
  task :deploy do
    include FlyIoRails::Utils

    # Get app name, creating one if necessary
    if File.exist? 'fly.toml'
      app = TOML.load_file('fly.toml')['app']
    else
      app = create_app
    end

    # ensure fly.toml and Dockerfile are present
    action = Fly::Actions.new(app)
    action.generate_toml if @app
    action.generate_fly_config unless File.exist? 'config/fly.rb'
    action.generate_dockerfile
    action.generate_dockerignore
    action.generate_raketask unless File.exist? 'lib/tasks/fly.rake'
    action.generate_procfile unless File.exist? 'Procfile.fly'

    # build and push an image
    out = FlyIoRails::Utils.tee "flyctl deploy --build-only --push --dockerfile #{action.dockerfile} --ignorefile #{action.ignorefile}"
    image = out[/image:\s+(.*)/, 1]&.strip

    exit 1 unless image

    if File.exist? 'main.tf'
      action.terraform(app, image)
    else
      action.generate_ipv4 if @app
      action.generate_ipv6 if @app
      action.deploy(app, image)
    end

    JSON.parse(`fly apps list --json`).each do |info|
      if info['Name'] == app
        60.times do
          response = Net::HTTP.get_response(URI::HTTPS.build(host: info['Hostname']))
          puts "Server status: #{response.code} #{response.message}"
          break
        rescue Errno::ECONNRESET
          sleep 0.5
        end
      end
    end
  end

  desc 'dbus daemon - used for IPC'
  task :dbus_deamon do
    IO.write '/var/lib/dbus/machine-id', `hostname`
    mkdir_p '/var/run/dbus'
    sh 'dbus-daemon --config-file=/usr/share/dbus-1/system.conf --print-address'
  end

  desc 'nats based service discovery'
  task :nats_publish, [:formation] do |task, args|
    nats_server = ENV['NATS_SERVER']

    # start nats server
    if nats_server == 'localhost'
      pid = spawn('nats-server')
      at_exit { Process.kill 7, pid }
    else
      open('/etc/hosts', 'a') do |file|
        host = "#{ENV['FLY_REGION']}-nats-server.local"
        file.puts "#{nats_server}\t#{host}"
        nats_server = host
      end
    end

    # determine our local 6pn network address
    address = IPSocket.getaddress('fly-local-6pn')

    # Determine which applications we need addresses for and
    # which applications we can provide addresses for.
    hosts = {}
    needs = []
    args[:formation].scan(/([-\w]+)=(\d+)/).each do |name, count|
      dnsname = "#{ENV['FLY_REGION']}-#{name}.local"
      needs << dnsname
      hosts[dnsname] = address unless count.to_i == 0
    end

    # share and collect hosts
    require 'nats/client'
    nats = NATS.connect(nats_server)

    nats.subscribe('query_hosts') do |msg|
      msg.respond hosts.to_json
    end

    update_hosts = Proc.new do |msg|
      addresses = JSON.parse(msg.data)

      open('/etc/hosts', 'r+') do |file|
        file.flock(File::LOCK_EX)
        contents = file.read

        addresses.each do |dnsname, address|
          file.puts "#{address}\t#{dnsname}" unless contents.include? dnsname
        end
      end

      needs -= hosts.keys
    end

    nats.request('query_hosts', &update_hosts)
    nats.subscribe('advertise_hosts', &update_hosts)

    nats.publish('advertise_hosts', hosts.to_json)

    at_exit { nats.close }

    # wait for dependencies to be available
    600.times do
      break if needs.empty?
      sleep 0.1
    end
  end

  desc 'Zeroconf/avahi/bonjour discovery'
  task :avahi_publish, [:formation] => :dbus_deamon do |task, args|
    pids = []
    pids << spawn('avahi-daemon')
    sleep 0.1

    ip = IPSocket.getaddress(Socket.gethostname)
    args[:formation].scan(/([-\w]+)=(\d+)/).each do |name, count|
      next if count.to_i == 0
      pids << spawn("avahi-publish -a -R #{ENV['FLY_REGION']}-#{name}.local #{ip}")
    end

    require 'resolv'
    100.times do
      begin
        map = {}
        args[:formation].scan(/([-\w]+)=(\d+)/).each do |name, count|
          dnsname = "#{ENV['FLY_REGION']}-#{name}.local"
          resolve = `avahi-resolve-host-name #{dnsname}`
          raise Resolv::ResolvError.new if $?.exitstatus > 0 or resolve.empty?
          map[dnsname] = resolve.split.last
        end

        open('/etc/hosts', 'a') do |hosts|
          map.each do |dnsname, address|
            hosts.puts "#{address} #{dnsname}"
          end
        end

        break
      rescue Resolv::ResolvError
        sleep 0.1
      end
    end

    at_exit do
      pids.each {|pid| Process.kill 7, pid}
    end
  end
end

# Alias, for convenience
desc 'Deploy fly application'
task deploy: 'fly:deploy'
