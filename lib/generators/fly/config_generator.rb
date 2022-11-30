require 'fly-rails/actions'

module Fly::Generators
class ConfigGenerator < Rails::Generators::Base
  include FlyIoRails::Utils

  # despite its name, this is a debug tool that will dump the config
  def generate_config
    action = Fly::Actions.new(@app, options)

    config = {}
    action.instance_variables.sort.each do |name|
      config[name] = action.instance_variable_get(name)
    end

    pp config
  end
end
end
