namespace :fly do
  desc 'Deploy fly application'
  task :deploy do
    out = FlyIoRails::Utils.tee 'fly deploy --build-only --push'
    image = out[/image:\s+(.*)/, 1]

    if image
      tf = IO.read('main.tf')
      tf[/^\s*image\s*=\s*"(.*?)"/, 1] = image.strip
      IO.write 'main.tf', tf

      ENV['FLY_API_TOKEN'] = `flyctl auth token`.chomp
      system 'terraform apply -auto-approve'
    end
  end
end

# Alias, for convenience
desc 'Deploy fly application'
task deploy: 'fly:deploy'
