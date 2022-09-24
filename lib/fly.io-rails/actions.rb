require 'thor'
require 'active_support'
require 'active_support/core_ext/string/inflections'
require 'fly.io-rails/machines'
require 'fly.io-rails/utils'
require 'fly.io-rails/dsl'

module Fly
  class Actions < Thor::Group
    include Thor::Actions
    include Thor::Base
    include Thor::Shell
    attr_accessor :options

    def initialize(app = nil)
      self.app = app if app

      @ruby_version = RUBY_VERSION
      @bundler_version = Bundler::VERSION
      @node = File.exist? 'node_modules'
      @yarn = File.exist? 'yarn.lock'
      @node_version = @node ? `node --version`.chomp.sub(/^v/, '') : '16.17.0'
      @org = Fly::Machines.org
      @regions = []

      @options = {}
      @destination_stack = [Dir.pwd]

      @config = Fly::DSL::Config.new
      if File.exist? 'config/fly.rb'
        @config.instance_eval IO.read('config/fly.rb')
      end
    end

    def app
      return @app if @app
      self.app = TOML.load_file('fly.toml')['app']
    end

    def app=(app)
      @app = app
      @appName = @app.gsub('-', '_').camelcase(:lower)
    end

    source_paths.push File::expand_path('../generators/templates', __dir__)

    def generate_toml
      app
      template 'fly.toml.erb', 'fly.toml'
    end

    def generate_dockerfile
      app
      template 'Dockerfile.erb', 'Dockerfile'
    end

    def generate_dockerignore
      app
      template 'dockerignore.erb', '.dockerignore'
    end

    def generate_terraform
      app
      template 'main.tf.erb', 'main.tf'
    end

    def generate_raketask
      app
      template 'fly.rake.erb', 'lib/tasks/fly.rake'
    end

    def generate_all
      generate_dockerfile
      generate_dockerignore
      generate_terraform
      generate_raketask
    end

    def generate_ipv4
      cmd = 'flyctl ips allocate-v4'
      say_status :run, cmd
      system cmd
    end

    def generate_ipv6
      cmd = 'flyctl ips allocate-v6'
      say_status :run, cmd
      system cmd
    end

    def create_volume(app, region, size)
      volume = "#{app.gsub('-', '_')}_volume"
      volumes = JSON.parse(`flyctl volumes list --json`).
        map {|volume| volume['Name']}

      unless volumes.include? volume
        cmd = "flyctl volumes create #{volume} --app #{app} --region #{region} --size #{size}"
        say_status :run, cmd
        system cmd
      end

      volume
    end

    def create_postgres(app, org, region, vm_size, volume_size, cluster_size)
      cmd = "flyctl postgres create --name #{app}-db --org #{org} --region #{region} --vm-size #{vm_size} --volume-size #{volume_size} --initial-cluster-size #{cluster_size}"
      say_status :run, cmd
      output = FlyIoRails::Utils.tee(cmd)
      output[%r{postgres://\S+}]
   end

    def create_redis(app, org, region, eviction)
      # see if redis is already defined
      name = `flyctl redis list`.lines[1..-2].map(&:split).
        find {|tokens| tokens[1] == org}&.first

      if name
        secret = `flyctl redis status #{name}`[%r{redis://\S+}]
        return secret if secret
      end

      # create a new redis
      cmd = "flyctl redis create --org #{org} --name #{app}-redis --region #{region} --no-replicas #{eviction} --plan #{@config.redis.plan}"
      say_status :run, cmd
      output = FlyIoRails::Utils.tee(cmd)
      output[%r{redis://\S+}]
    end

    def release(app, config)
      start = Fly::Machines.create_and_start_machine(app, config: config)
      machine = start[:id]

      if !machine
	STDERR.puts 'Error starting release machine'
	PP.pp start, STDERR
	exit 1
      end

      status = Fly::Machines.wait_for_machine app, machine,
        timeout: 60, state: 'started'

      # wait for release to copmlete
      status = nil
      5.times do
        status = Fly::Machines.wait_for_machine app, machine,
          timeout: 60, state: 'stopped'
        return machine if status[:ok]
      end

      # wait for release to copmlete
      event = nil
      90.times do
	sleep 1
	status = Fly::Machines.get_a_machine app, machine
	event = status[:events]&.first
	return machine if event && event[:type] == 'exit'
      end

      STDERR.puts event.to_json
      exit 1
    end

    def deploy(app, image) 
      regions = JSON.parse(`flyctl regions list --json`)['Regions'].
        map {|region| region['Code']} rescue []
      region = regions.first || 'iad'

      secrets = JSON.parse(`flyctl secrets list --json`).
        map {|secret| secret["Name"]}

      config = {
        region: region,
        app: app,
        name: "#{app}-machine",
        image: image,
        guest: {
          cpus: @config.machine.cpus,
          cpu_kind: @config.machine.cpu_kind,
          memory_mb: @config.machine.memory_mb
        },
        services: [
	  {
	    ports: [
	      {port: 443, handlers: ["tls", "http"]},
	      {port: 80, handlers: ["http"]}
	    ],
	    protocol: "tcp",
	    internal_port: 8080
	  } 
        ]
      }

      database = YAML.load_file('config/database.yml').
        dig('production', 'adapter') rescue nil
      cable = YAML.load_file('config/cable.yml').
        dig('production', 'adapter') rescue nil

      if database == 'sqlite3'
        volume = create_volume(app, region, @config.sqlite3.size) 

        config[:mounts] = [
          { volume: volume, path: '/mnt/volume' }
        ]

        config[:env] = {
          "DATABASE_URL" => "sqlite3:///mnt/volume/production.sqlite3"
        }
      elsif database == 'postgresql' and not secrets.include? 'DATABASE_URL'
        secret = create_postgres(app, @org, region,
          @config.postgres.vm_size,
          @config.postgres.volume_size,
          @config.postgres.initial_cluster_size)

        if secret
          cmd = "flyctl secrets set --stage DATABASE_URL=#{secret}"
          say_status :run, cmd
          system cmd
        end
      end

      # Enable redis if mentioned as a cache provider or a cable provider.
      # Set eviction policy to true if a cache provider, else false.
      eviction = nil

      if (YAML.load_file('config/cable.yml').dig('production', 'adapter') rescue false)
        eviction = '--disable-eviction'
      end

      if (IO.read('config/environments/production.rb') =~ /redis/i rescue false)
        eviction = '--enable-eviction'
      end

      if eviction and not secrets.include? 'REDIS_URL'
        secret = create_redis(app, @org, region, eviction)

        if secret
          cmd = "flyctl secrets set --stage REDIS_URL=#{secret}"
          say_status :run, cmd
          system cmd
        end
      end

      # build config for release machine, overriding server command
      release_config = config.dup
      release_config.delete :services
      release_config.delete :mounts
      release_config[:env] = { 'SERVER_COMMAND' => 'bin/rails fly:release' }

      # perform release
      say_status :fly, release_config[:env]['SERVER_COMMAND']
      machine = release(app, release_config)
      Fly::Machines.delete_machine app, machine if machine

      # start proxy, if necessary
      endpoint = Fly::Machines::fly_api_hostname!

      # stop previous instances
      JSON.parse(`fly machines list --json`).each do |list|
        next if list['id'] == machine
        system "fly machines remove --force #{list['id']}"
      end

      # start app
      say_status :fly, "start #{app}"
      start = Fly::Machines.create_and_start_machine(app, config: config)
      machine = start[:id]

      if !machine
	STDERR.puts 'Error starting application'
	PP.pp start, STDERR
	exit 1
      end

      5.times do
	status = Fly::Machines.wait_for_machine app, machine,
          timeout: 60, status: 'started'
	return if status[:ok]
      end

      STDERR.puts 'Timeout waiting for application to start'
    end

    def terraform(app, image) 
      # update main.tf with the image name
      tf = IO.read('main.tf')
      tf[/^\s*image\s*=\s*"(.*?)"/, 1] = image.strip
      IO.write 'main.tf', tf

      # find first machine in terraform config file
      machines = Fly::HCL.parse(IO.read('main.tf')).find {|block|
	block.keys.first == :resource and
	block.values.first.keys.first == 'fly_machine'}

      # extract HCL configuration for the machine
      config = machines.values.first.values.first.values.first

      # delete HCL specific configuration items
      %i(services for_each region app name depends_on).each do |key|
	 config.delete key
      end

      # move machine configuration into guest object
      config[:guest] = {
	cpus: config.delete(:cpus),
	memory_mb: config.delete(:memorymb),
	cpu_kind: config.delete(:cputype)
      }

      # release machines should have no services or mounts
      config.delete :services
      config.delete :mounts

      # override start command
      config[:env] ||= {}
      config[:env]['SERVER_COMMAND'] = 'bin/rails fly:release'

      # start proxy, if necessary
      endpoint = Fly::Machines::fly_api_hostname!

      # start release machine
      STDERR.puts "--> #{config[:env]['SERVER_COMMAND']}"
      start = Fly::Machines.create_and_start_machine(app, config: config)
      machine = start[:id]

      if !machine
	STDERR.puts 'Error starting release machine'
	PP.pp start, STDERR
	exit 1
      end

      # wait for release to copmlete
      event = nil
      90.times do
	sleep 1
	status = Fly::Machines.get_a_machine app, machine
	event = status[:events]&.first
	break if event && event[:type] == 'exit'
      end

      # extract exit code
      exit_code = event.dig(:request, :exit_event, :exit_code)
	       
      if exit_code == 0
	# delete release machine
	Fly::Machines.delete_machine app, machine

	# use terraform apply to deploy
	ENV['FLY_API_TOKEN'] = `flyctl auth token`.chomp
	ENV['FLY_HTTP_ENDPOINT'] = endpoint if endpoint
	system 'terraform apply -auto-approve'
      else
	STDERR.puts 'Error performing release'
	STDERR.puts (exit_code ? {exit_code: exit_code} : event).inspect
	STDERR.puts "run 'flyctl logs --instance #{machine}' for more information"
	exit 1
      end
    end
  end
end
