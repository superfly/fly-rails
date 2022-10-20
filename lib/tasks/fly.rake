require 'fly.io-rails/machines'
require 'fly.io-rails/hcl'
require 'fly.io-rails/actions'
require 'toml'

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
    action.generate_dockerfile unless File.exist? 'Dockerfile'
    action.generate_dockerignore unless File.exist? '.dockerignore'
    action.generate_raketask unless File.exist? 'lib/tasks/fly.rake'
    action.generate_procfile unless File.exist? 'Procfile.fly'

    # build and push an image
    out = FlyIoRails::Utils.tee 'fly deploy --build-only --push'
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

  desc 'Zeroconf/avahi/bonjour discovery'
  task :avahi_publish, [:formation, :list] => :dbus_deamon do |task, args|
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
        args[:list].scan(/([-\w]+)=(\d+)/).each do |name, count|
          dnsname = "#{ENV['FLY_REGION']}-#{name}.local"
          ping = `ping -q -c 1 -t 1 #{dnsname}`
          raise Resolv::ResolvError.new if $?.exitstatus > 0 or ping.empty?
          map[dnsname] = ping[/\((.*?)\)/, 1]
        end

        open('/etc/hosts', 'a') do |hosts|
          map.each do |dnsname, address|
            hosts.puts "#{address} #{dnsname}"
          end
        end
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
