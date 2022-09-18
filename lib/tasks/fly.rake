require 'fly.io-rails/machines'
require 'fly.io-rails/hcl'

namespace :fly do
  desc 'Deploy fly application'
  task :deploy do
    # build and push an image
    out = FlyIoRails::Utils.tee 'fly deploy --build-only --push'
    image = out[/image:\s+(.*)/, 1]

    exit 1 unless image

    # update main.tf with the image name
    tf = IO.read('main.tf')
    tf[/^\s*image\s*=\s*"(.*?)"/, 1] = image.strip
    IO.write 'main.tf', tf

    # find first machine in terraform config file
    machines = Fly::HCL.parse(IO.read('main.tf')).find {|block|
      block.keys.first == :resource and
      block.values.first.keys.first == 'fly_machine'}

    # extract HCL configuration for the machine
    config = machines.values.first.values.first.values.first

    # extract fly application name
    app = config[:app]

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

    # start release machine
    STDERR.puts "--> #{config[:env]['SERVER_COMMAND']}"
    start = Fly::Machines.create_start_machine(app, config: config)
    machine = start[:id]

    if !machine
      STDERR.puts 'Error starting release machine'
      PP.pp start, STDERR
      exit 1
    end

    # wait for release to copmlete
    event = nil
    90.times do
      sleep 1
      status = Fly::Machines.get_a_machine app, machine
      event = status[:events]&.first
      break if event && event[:type] == 'exit'
    end

    # extract exit code
    exit_code = event.dig(:request, :exit_event, :exit_code)
	     
    if exit_code == 0
      # delete release machine
      Fly::Machines.delete_machine app, machine

      # use terraform apply to deploy
      ENV['FLY_API_TOKEN'] = `flyctl auth token`.chomp
      system 'terraform apply -auto-approve'
    else
      STDERR.puts 'Error performing release'
      STDERR.puts (exit_code ? {exit_code: exit_code} : event).inspect
      STDERR.puts "run 'flyctl logs --instance #{machine}' for more information"
      exit 1
    end
  end
end

# Alias, for convenience
desc 'Deploy fly application'
task deploy: 'fly:deploy'
