require 'fly.io-rails/actions'

module Fly::Generators
class AppGenerator < Rails::Generators::Base
  include FlyIoRails::Utils

  class_option :name, type: :string, required: false
  class_option :org, type: :string, default: 'personal'
  class_option :region, type: :array, repeatable: true, default: []
  class_option :nomad, type: :boolean, default: false

  class_option :litefs, type: :boolean, default: false
  class_option :passenger, type: :boolean, default: false

  def generate_app
    source_paths.push File.expand_path('../templates', __dir__)

    create_app(**options.symbolize_keys)

    action = Fly::Actions.new(@app, options)

    action.generate_toml
    action.generate_fly_config unless File.exist? 'config/fly.rb'
    action.generate_dockerfile unless File.exist? 'Dockerfile'
    action.generate_dockerignore unless File.exist? '.dockerignore'
    action.generate_nginx_conf unless File.exist? 'config/nginx.conf'
    action.generate_raketask unless File.exist? 'lib/tasks/fly.rake'
    action.generate_procfile unless File.exist? 'Procfile.rake'
    action.generate_litefs if options[:litefs] and not File.exist? 'config/litefs'
    action.generate_patches
    action.generate_ipv4
    action.generate_ipv6

    action.launch(@app)
  end
end
end
