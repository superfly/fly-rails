require 'fly.io-rails/machines'
require 'fly.io-rails/hcl'
require 'fly.io-rails/actions'
require 'toml'

namespace :fly do
  desc 'Deploy fly application'
  task :deploy do
    include FlyIoRails::Utils

    # Get app name, creating one if necessary
    if File.exist? 'fly.toml'
      app = TOML.load_file('fly.toml')['app']
    else
      app = create_app
    end

    # ensure fly.toml and Dockerfile are present
    action = Fly::Actions.new(app)
    action.generate_toml if @app
    action.generate_fly_config unless File.exist? 'config/fly.rb'
    action.generate_dockerfile unless File.exist? 'Dockerfile'
    action.generate_dockerignore unless File.exist? '.dockerignore'
    action.generate_raketask unless File.exist? 'lib/tasks/fly.rake'

    # build and push an image
    out = FlyIoRails::Utils.tee 'fly deploy --build-only --push'
    image = out[/image:\s+(.*)/, 1]&.strip

    exit 1 unless image

    if File.exist? 'main.tf'
      action.terraform(app, image)
    else
      action.generate_ipv4 if @app
      action.generate_ipv6 if @app
      action.deploy(app, image)
    end
  end
end

# Alias, for convenience
desc 'Deploy fly application'
task deploy: 'fly:deploy'
