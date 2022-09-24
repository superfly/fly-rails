require 'fly.io-rails/actions'

module Fly::Generators
class AppGenerator < Rails::Generators::Base
  include FlyIoRails::Utils

  class_option :name, type: :string, required: false
  class_option :org, type: :string, default: 'personal'
  class_option :region, type: :array, repeatable: true, default: []

  def generate_app
    source_paths.push File.expand_path('../templates', __dir__)

    create_app(options)

    action = Fly::Actions.new(@app)

    action.generate_key
  end
end
end
