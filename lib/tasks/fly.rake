namespace :fly do
  desc 'Launch a new app'
  task :launch do
    sh 'flyctl launch'

    # note: Rake task argument syntax isn't particularly user friendy,
    # but Rake is a Ruby program and we have full access to ARGV,
    # meaning we can do our own thing with OptionParser or whatever.
    # The only real caveat if we do so is that we need to exit the
    # program at the completion of the task lest Rails tries to interpet
    # the next argument as the name of the next task to execute.

    Rake.rake_output_message 'Customizing Dockerfile...'

    exit
  end

  desc 'Deploy fly application'
  task :deploy do
    sh 'flyctl deploy'
  end
end

# Alias, for convenience
desc 'Deploy fly application'
task deploy: 'fly:deploy'