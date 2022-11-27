require 'open3'
require 'thor'
require 'toml'
require 'active_support'
require 'active_support/core_ext/string/inflections'
require 'fly.io-rails/machines'
require 'fly.io-rails/utils'
require 'fly.io-rails/dsl'
require 'fly.io-rails/scanner'

module Fly
  class Actions < Thor::Group
    include Thor::Actions
    include Thor::Base
    include Thor::Shell
    include Fly::Scanner
    attr_accessor :options, :dockerfile, :ignorefile

    def initialize(app=nil, options={})
      # placate thor
      @options = {}
      @destination_stack = [Dir.pwd]

      # extract options
      app ? self.app = app : app = self.app
      regions = options[:region]&.flatten || []
      @avahi = options[:avahi]
      @litefs = options[:litefs]
      @nats = options[:nats]
      @nomad = options[:nomad]
      @passenger = options[:passenger]
      @serverless = options[:serverless]
      @eject = options[:eject]

      # prepare template variables
      @ruby_version = RUBY_VERSION
      @bundler_version = Bundler::VERSION
      @node = File.exist? 'node_modules'
      @yarn = File.exist? 'yarn.lock'
      @node_version = @node ? `node --version`.chomp.sub(/^v/, '') : '16.17.0'
      @yarn_version = @yarn ? `yarn --version`.chomp : 'latest'
      @org = Fly::Machines.org

      @set_stage = @nomad ? 'set' : 'set --stage'

      # determine region
      if !regions or regions.empty?
        @regions = JSON.parse(`flyctl regions list --json --app #{app}`)['Regions'].
          map {|region| region['Code']} rescue []
      else
        @regions = regions
      end

      @region = @regions.first || 'iad'
      @regions = [@region] if @regions.empty?

      # Process DSL
      @config = Fly::DSL::Config.new
      if File.exist? 'config/fly.rb'
        @config.instance_eval IO.read('config/fly.rb')
        @image = @config.image
      end

      # set additional variables based on application source
      scan_rails_app
      @redis = :internal if options[:redis]
      if File.exist? 'Procfile.fly'
        @redis = :internal if IO.read('Procfile.fly') =~ /^redis/
      end

      if options[:anycable] and not @anycable
        # read and remove original config
        original_config = YAML.load_file 'config/cable.yml'
        File.unlink 'config/cable.yml'

        # add and configure anycable-rails
        say_status :run, 'bundle add anycable-rails'
        Bundler.with_original_env do
          system 'bundle add anycable-rails'
          system 'bin/rails generate anycable:setup --skip-heroku --skip-procfile-dev --skip-jwt --devenv=skip'
        end

        # insert action_cable_meta_tag
        insert_into_file 'app/views/layouts/application.html.erb',
          "    <%= action_cable_meta_tag %>\n",
          after: "<%= csp_meta_tag %>\n"

        # copy production environment to original config
        anycable_config = YAML.load_file 'config/cable.yml'
        original_config['production'] = anycable_config['production']
        File.write 'config/cable.yml', YAML.dump(original_config)

        @anycable = true
      end

      @nginx = @passenger || (@anycable and not @deploy)

      # determine processes
      @procs = {web: 'bin/rails server'}
      @procs[:web] = "nginx -g 'daemon off;'" if @nginx
      @procs[:rails] = "bin/rails server -p 8081" if @nginx and not @passenger
      @procs[:worker] = 'bundle exec sidekiq' if @sidekiq
      @procs[:redis] = 'redis-server /etc/redis/redis.conf' if @redis == :internal
      @procs.merge! 'anycable-rpc': 'bundle exec anycable --rpc-host=0.0.0.0:50051',
        'anycable-go': 'env /usr/local/bin/anycable-go --port=8082 --host 0.0.0.0  --rpc_host=localhost:50051' if @anycable
    end

    def app
      return @app if @app
      self.app = TOML.load_file('fly.toml')['app']
    end

    def render template
      template = ERB.new(IO.read(File.expand_path(template, source_paths.last)), trim_mode: '-')
      template.result(binding).chomp
    end

    def app_template template_file, destination
      app
      template template_file, destination
    end

    def app=(app)
      @app = app
      @appName = @app.gsub('-', '_').camelcase(:lower)
    end

    source_paths.push File::expand_path('../generators/templates', __dir__)

    def generate_toml
      app_template 'fly.toml.erb', 'fly.toml'
    end

    def generate_fly_config
      select_image
      app_template 'fly.rb.erb', 'config/fly.rb'
    end

    def select_image
      return @image if @image and @image.include? ":#{@ruby_version}-"

      tags = []

      debian_releases = %w(stretch buster bullseye bookworm) 
              
      Net::HTTP.start('quay.io', 443, use_ssl: true) do |http|
        (1..).each do |page|
          request = Net::HTTP::Get.new "/api/v1/repository/evl.ms/fullstaq-ruby/tag/?page=#{page}&limit=100"
          response = http.request request
          body = JSON.parse(response.body)
          tags += body['tags'].map {|tag| tag['name']}.grep /jemalloc-\w+-slim/
          break unless body['has_additional']
        end
      end 
          
      ruby_releases = tags.group_by {|tag| tag.split('-').first}.
        map do |release, tags|
          [release, tags.max_by {|tag| debian_releases.find_index(tag[/jemalloc-(\w+)-slim/, 1]) || -1}]
        end.sort.to_h

      unless ruby_releases[@ruby_version]
        @ruby_version = ruby_releases.keys.find {|release| release >= @ruby_version} ||
          ruby_releases.keys.last
      end

      @image = 'quay.io/evl.ms/fullstaq-ruby:' + ruby_releases[@ruby_version]
    end

    def generate_dockerfile
      if @eject or File.exist? 'Dockerfile'
        @dockerfile = 'Dockerfile'
      else
        tmpfile = Tempfile.new('Dockerfile')
        @dockerfile = tmpfile.path
        tmpfile.unlink
        at_exit { File.unlink @dockerfile }
      end

      if @eject or not File.exist? @dockerfile
        select_image
        app_template 'Dockerfile.erb', @dockerfile
      end
    end

    def generate_dockerignore
      if @eject or File.exist? '.dockerignore'
        @ignorefile = '.dockerignore'
      elsif File.exist? '.gitignore'
        @ignorefile = '.gitignore'
      else
        tmpfile = Tempfile.new('Dockerignore')
        @ignoreile = tmpfile.path
        tmpfile.unlink
        at_exit { Filee.unlink @ignorefile }
      end

      if @eject or not File.exist? @ignorefile
        app_template 'dockerignore.erb', @ignorefile
      end
    end

    def generate_nginx_conf
      return unless @passenger
      app_template 'nginx.conf.erb', 'config/nginx.conf'

      if @serverless
        app_template 'hook_detached_process.erb', 'config/hook_detached_process'
        FileUtils.chmod 'u+x', 'config/hook_detached_process'
      end
    end

    def generate_terraform
      app_template 'main.tf.erb', 'main.tf'
    end

    def generate_raketask
      app_template 'fly.rake.erb', 'lib/tasks/fly.rake'
    end

    def generate_procfile
      return unless @procs.length > 1
      app_template 'Procfile.fly.erb', 'Procfile.fly'
    end

    def generate_litefs
      app_template 'litefs.yml.erb', 'config/litefs.yml'
    end

    def generate_key
      credentials = nil
      if File.exist? 'config/credentials/production.key'
        credentials = 'config/credentials/production.key'
      elsif File.exist? 'config/master.key'
        credentials = 'config/master.key'
      end
  
      if credentials
        say_status :run, "flyctl secrets #{@set_stage} RAILS_MASTER_KEY from #{credentials}"
        system "flyctl secrets #{@set_stage} RAILS_MASTER_KEY=#{IO.read(credentials).chomp}"
        puts
      end
    end

    def generate_patches
      if false # @redis_cable and not @anycable and @redis != :internal and
        not File.exist? 'config/initializers/action_cable.rb'

        app
        template 'patches/action_cable.rb', 'config/initializers/action_cable.rb'
      end
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
      name = "#{app.gsub('-', '_')}_volume"
      volumes = JSON.parse(`flyctl volumes list --json`)

      volume = volumes.find {|volume| volume['Name'] == name and volume['Region'] == region}
      unless volume
        cmd = "flyctl volumes create #{name} --app #{app} --region #{region} --size #{size}"
        say_status :run, cmd
        system cmd
        volumes = JSON.parse(`flyctl volumes list --json`)
        volume = volumes.find {|volume| volume['Name'] == name and volume['Region'] == region}
      end

      volume && volume['id']
    end

    def create_postgres(app, org, region, vm_size, volume_size, cluster_size)
      cmd = "flyctl postgres create --name #{app}-db --org #{org} --region #{region} --vm-size #{vm_size} --volume-size #{volume_size} --initial-cluster-size #{cluster_size}"
      cmd += ' --machines' unless @nomad
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
      output[%r{redis://[-\w:@.]+}]
    end

    def bundle_gems
      if @anycable and not @gemfile.include? 'anycable-rails'
        cmd = 'bundle add anycable-rails'
        say_status :run, cmd
        system cmd
        exit $?.exitstatus unless $?.success?
      end
    end

    def release(app, options)
      start = Fly::Machines.create_and_start_machine(app, options)
      machine = start[:id]

      if not machine
        STDERR.puts 'Error starting release machine'
        PP.pp start, STDERR
        exit 1
      end

      status = Fly::Machines.wait_for_machine app, machine,
        timeout: 60, state: 'started'

      # wait for release to copmlete
      5.times do
        status = Fly::Machines.wait_for_machine app, machine,
          instance_id: start[:instance_id], timeout: 60, state: 'stopped'
        break if status[:ok]
      end

      if status and status[:ok]
        event = nil
        300.times do
          status = Fly::Machines.get_a_machine app, start[:id]
          event = status[:events]&.first
          break if event[:type] == 'exit'
          sleep 0.2
        end

        exit_code = event&.dig(:request, :exit_event, :exit_code)
        Fly::Machines.delete_machine app, machine if machine
        return event, exit_code, machine
      else
        return status, nil, nil
      end
    end

    def launch(app)
      secrets = JSON.parse(`flyctl secrets list --json`).
        map {|secret| secret["Name"]}

      unless secrets.include? 'RAILS_MASTER_KEY'
        generate_key
      end

      if @sqlite3
        if @litefs
          @regions.each do |region|
            @volume = create_volume(app, region, @config.sqlite3.size) 
          end
        else
          @volume = create_volume(app, @region, @config.sqlite3.size) 
        end
      elsif @postgresql and not secrets.include? 'DATABASE_URL'
        unless (IO.read('config/fly.rb').include?('postgres') rescue true)
          source_paths.each do |path|
            template = File.join(path, 'fly.rb.erb')
            next unless File.exist? template
            insert = IO.read(template)[/<% if @postgresql -%>\n(.*?)<% end/m, 1]
            append_to_file 'config/fly.rb', insert if insert
            break
          end
        end

        secret = create_postgres(app, @org, @region,
          @config.postgres.vm_size,
          @config.postgres.volume_size,
          @config.postgres.initial_cluster_size)

        if secret
          cmd = "flyctl secrets #{@set_stage} DATABASE_URL=#{secret}"
          say_status :run, cmd
          system cmd
        end
      end

      if @redis and @redis != :internal and not secrets.include? 'REDIS_URL'
        # Set eviction policy to true if a cache provider, else false.
        eviction = @redis_cache ? '--enable-eviction' : '--disable-eviction'

        secret = create_redis(app, @org, @region, eviction)

        if secret
          cmd = "flyctl secrets #{@set_stage} REDIS_URL=#{secret}"
          say_status :run, cmd
          system cmd
        end
      end
    end

    def deploy(app, image)
      launch(app)

      # default config
      config = {
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

      # only run release step if there is a non-empty release task in fly.rake
      if (IO.read('lib/tasks/fly.rake') rescue '') =~ /^\s*task[ \t]*+:?release"?[ \t]*\S/
        # build config for release machine, overriding server command
        release_config = config.dup
        release_config.delete :services
        release_config.delete :mounts
        release_config[:env] = { 'SERVER_COMMAND' => 'bin/rails fly:release' }

        # perform release
        say_status :fly, release_config[:env]['SERVER_COMMAND']
        event, exit_code, machine = release(app, region: @region, config: release_config)

        if exit_code != 0
          STDERR.puts 'Error performing release'
          STDERR.puts (exit_code ? {exit_code: exit_code} : event).inspect
          STDERR.puts "run 'flyctl logs --instance #{machine}' for more information"
          exit 1
        end
      end

      # start proxy, if necessary
      endpoint = Fly::Machines::fly_api_hostname!

      # stop previous instances - list will fail on first run
      stdout, stderr, status = Open3.capture3('fly machines list --json')
      existing_machines = []
      unless stdout.empty?
        JSON.parse(stdout).each do |list|
          existing_machines << list['name']
          next if list['id'] == machine or list['state'] == 'destroyed'
          cmd = "fly machines remove --force #{list['id']}"
          say_status :run, cmd
          system cmd
        end
      end

      # configure sqlite3 (can be overridden by fly.toml)
      if @sqlite3
        config[:mounts] = [
          { volume: @volume, path: '/mnt/volume' }
        ]

        config[:env] = {
          "DATABASE_URL" => "sqlite3:///mnt/volume/production.sqlite3"
        }

        if @litefs
          config[:env]['DATABASE_URL'] = "sqlite3:///data/production.sqlite3"
        end
      end

      # process toml overrides
      toml = (TOML.load_file('fly.toml') rescue {})
      config[:env] = toml['env'] if toml['env']
      config[:services] = toml['services'] if toml['services']
      if toml['mounts']
        mounts = toml['mounts']
        volume = JSON.parse(`flyctl volumes list --json`).
          find {|volume| volume['Name'] == mounts['source'] and volume['Region'] == @region}
        if volume
          config[:mounts] = [ { volume: volume['id'], path: mounts['destination'] } ]
        else
          STDERR.puts "volume #{mounts['source']} not found in region #{@region}"
          exit 1
        end
      end

      # start app
      machines = {}
      options = {region: @region, config: config}
      say_status :fly, "start #{app}"
      if not toml['processes'] or toml['processes'].empty?
        options[:name] = "#{app}-machine"
        taken = existing_machines.find {|name| name.start_with? options[:name]}
        options[:name] = taken == options[:name] ? "#{taken}-2" : taken.next if taken

        start = Fly::Machines.create_and_start_machine(app, options)
        machines['app'] = start[:id] 
      else
        config[:env] ||= {}
        config[:env]['NATS_SERVER'] = 'localhost'
        toml['processes'].each do |name, entrypoint|
          options[:name] = "#{app}-machine-#{name}"
          taken = existing_machines.find {|name| name.start_with? options[:name]}
          options[:name] = taken == options[:name] ? "#{taken}-2" : taken.next if taken

          config[:env]['SERVER_COMMAND'] = entrypoint
          start = Fly::Machines.create_and_start_machine(app, options)

          if start['error']
            STDERR.puts "ERROR: #{start['error']}"
            exit 1
          end

          machines[name] = start[:id] 

          config.delete :mounts
          config.delete :services

          if config[:env]['NATS_SERVER'] = 'localhost'
            config[:env]['NATS_SERVER'] = start[:private_ip] 
          end
        end
      end

      if machines.empty?
        STDERR.puts 'Error starting application'
        PP.pp start, STDERR
        exit 1
      end

      timeout = Time.now + 300
      while Time.now < timeout and not machines.empty?
        machines.each do |name, machine|
          status = Fly::Machines.wait_for_machine app, machine,
           timeout: 10, status: 'started'
          machines.delete name if status[:ok]
        end
      end

      unless machines.empty?
        STDERR.puts 'Timeout waiting for application to start'
      end
    end

    def terraform(app, image) 
      # find first machine using the image ref in terraform config file
      machine = Fly::HCL.parse(IO.read('main.tf')).
        map {|block| block.dig(:resource, 'fly_machine')}.compact.
        find {|machine| machine.values.first[:image] == 'var.image_ref'}
      if not machine
        STDERR.puts 'unable to find fly_machine with image = var.image_ref in main.rf'
        exit 1
      end

      # extract HCL configuration for the machine
      config = machine.values.first

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

      # fill in image
      config[:image] = image

      # start proxy, if necessary
      endpoint = Fly::Machines::fly_api_hostname!

      # perform release, if necessary
      if (IO.read('lib/tasks/fly.rake') rescue '') =~ /^\s*task[ \t]*+:?release"?[ \t]*\S/
        say_status :fly, config[:env]['SERVER_COMMAND']
        event, exit_code, machine = release(app, region: @region, config: config)
      else
        exit_code = 0
      end

      if exit_code == 0
        # use terraform apply to deploy
        ENV['FLY_API_TOKEN'] = `flyctl auth token`.chomp
        ENV['FLY_HTTP_ENDPOINT'] = endpoint if endpoint
        system "terraform apply -auto-approve -var=\"image_ref=#{image}\""
      else
        STDERR.puts 'Error performing release'
        STDERR.puts (exit_code ? {exit_code: exit_code} : event).inspect
        STDERR.puts "run 'flyctl logs --instance #{machine}' for more information"
        exit 1
      end
    end
  end
end
