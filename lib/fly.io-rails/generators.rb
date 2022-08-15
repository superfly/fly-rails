require 'rails/generators'
require 'rails/generators/channel/channel_generator'
require 'rails/generators/job/job_generator'

class Rails::Generators::ChannelGenerator
  def configure_fly
    STDERR.puts 'Configuring fly...'
  end
end

class Rails::Generators::JobGenerator
  def configure_fly
    STDERR.puts 'Configuring fly...'
  end
end
