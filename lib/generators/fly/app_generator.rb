require 'fly.io-rails/actions'

module Fly::Generators
class AppGenerator < Rails::Generators::Base
  include FlyIoRails::Utils

  class_option :name, type: :string, required: false
  class_option :org, type: :string, default: 'personal'
  class_option :region, type: :array, repeatable: true, default: []

  def generate_app
    source_paths.push File.expand_path('../templates', __dir__)

    create_app(options[:name], options[:org], options)

    action = Fly::Actions.new(@app, options[:region])

    action.generate_fly_config unless File.exist? 'config/fly.rb'
    action.generate_dockerfile unless File.exist? 'Dockerfile'
    action.generate_dockerignore unless File.exist? '.dockerignore'
    action.generate_raketask unless File.exist? 'lib/tasks/fly.rake'
    action.generate_patches
    action.generate_ipv4
    action.generate_ipv6
    action.generate_key
    
  end
end
end
