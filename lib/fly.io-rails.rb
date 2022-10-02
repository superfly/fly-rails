require 'rails'
require 'fly.io-rails/generators'
require 'fly.io-rails/utils'

class FlyIoRailtie < Rails::Railtie
  # load rake tasks
  rake_tasks do
    Dir[File.expand_path('tasks/*.rake', __dir__)].each do |file|
      load file
    end
  end

  # set FLY_IMAGE_NAME on nomad vms
  if not ENV['FLY_IMAGE_NAME'] and ENV['FLY_APP_NAME'] and ENV['FLY_API_TOKEN']
    ENV['FLY_IMAGE_REF'] = Fly::Machines.graphql(%{
      query {
	app(name: "#{ENV['FLY_APP_NAME']}") {
	  currentRelease {
	    imageRef
	  }
	}
      }
    }).dig(:data, :app, :currentRelease, :imageRef)
  end
end
