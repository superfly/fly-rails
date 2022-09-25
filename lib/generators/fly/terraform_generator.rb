require 'fly.io-rails/actions'

module Fly::Generators
class TerraformGenerator < Rails::Generators::Base
  include FlyIoRails::Utils

  class_option :name, type: :string, required: false
  class_option :org, type: :string, default: 'personal'
  class_option :region, type: :array, repeatable: true, default: []

  def terraform
    source_paths.push File.expand_path('../templates', __dir__)

    create_app(options[:name], options[:org], options[:region])

    action = Fly::Actions.new(@app, options[:region])
    
    action.generate_toml
    action.generate_dockerfile
    action.generate_dockerignore
    action.generate_terraform
    action.generate_raketask
    action.generate_patches

    action.generate_key

    tee 'terraform init'
  end
end
end