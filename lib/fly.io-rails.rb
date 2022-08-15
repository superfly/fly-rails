require 'rails'
require 'fly.io-rails/generators'

class FlyIoRailtie < Rails::Railtie
  rake_tasks do
    Dir[File.expand_path('tasks/*.rake', __dir__)].each do |file|
      load file
    end
  end
end
