require 'fly.io-rails/actions'

module Fly::Generators
class AppGenerator < Rails::Generators::Base
  include FlyIoRails::Utils

  class_option :name, type: :string, required: false
  class_option :org, type: :string, default: 'personal'
  class_option :region, type: :array, repeatable: true, default: []
  class_option :nomad, type: :boolean, default: false

  class_option :anycable, type: :boolean, default: false
  class_option :avahi, type: :boolean, default: false
  class_option :litefs, type: :boolean, default: false
  class_option :nats, type: :boolean, default: false
  class_option :redis, type: :boolean, default: false
  class_option :passenger, type: :boolean, default: false
  class_option :serverless, type: :boolean, default: false

  def generate_app
    source_paths.push File.expand_path('../templates', __dir__)

    # the plan is to make eject an option, default to false, but until
    # that is ready, have generate fly:app always eject
    options = options.to_h.dup
    options[:eject] = options[:nomad]

    if File.exist? 'fly.toml'
      toml = TOML.load_file('fly.toml')
      options[:name] ||= toml['app']
      apps = JSON.parse(`flyctl list apps --json`) rescue []

      if toml.keys.length == 1
        if options[:name] != toml['app']
          # replace existing fly.toml
          File.unlink 'fly.toml'
          create_app(**options.symbolize_keys)
        elsif not apps.any? {|item| item['ID'] == options[:name]}
          create_app(**options.symbolize_keys)
        end
      elsif options[:name] != toml['app']
        say_status "fly:app", "Using the name in the existing toml file", :red
        options[:name] = toml['app']
      end
    else
      create_app(**options.symbolize_keys)
    end

    action = Fly::Actions.new(@app, options)

    action.generate_toml
    action.generate_fly_config unless File.exist? 'config/fly.rb'

    if options[:eject]
      action.generate_dockerfile unless File.exist? 'Dockerfile'
      action.generate_dockerignore unless File.exist? '.dockerignore'
      action.generate_nginx_conf unless File.exist? 'config/nginx.conf'
      action.generate_raketask unless File.exist? 'lib/tasks/fly.rake'
      action.generate_procfile unless File.exist? 'Procfile.rake'
      action.generate_litefs if options[:litefs] and not File.exist? 'config/litefs'
      action.generate_patches
    end

    ips = `flyctl ips list`.strip.lines[1..].map(&:split).map(&:first)
    action.generate_ipv4 unless ips.include? 'v4'
    action.generate_ipv6 unless ips.include? 'v6'

    action.launch(action.app)
  end
end
end
