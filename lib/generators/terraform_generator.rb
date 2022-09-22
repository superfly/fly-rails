require 'open3'
require 'fly.io-rails/machines'

class TerraformGenerator < Rails::Generators::Base
  include FlyIoRails::Utils

  class_option :name, type: :string, required: false
  class_option :org, type: :string, default: 'personal'
  class_option :region, type: :array, repeatable: true, default: []

  def terraform
    source_paths.push File.expand_path('./templates', __dir__)

    cmd = if options[:name]
      "flyctl apps create #{options[:name].inspect} --org #{options[:org].inspect}"
    else
      "flyctl apps create --generate-name --org #{options[:org].inspect}"
    end

    output = tee cmd
    exit 1 unless output =~ /^New app created: /

    @app = output.split.last
    template 'fly.toml.erb', 'fly.toml'

    if options[:region].empty?
      @regions = JSON.parse(`flyctl regions list --json`)['Regions'].
        map {|region| region['Code']}
    else
      @regions = options[:regions].flatten
    end

    @ruby_version = RUBY_VERSION
    @bundler_version = Bundler::VERSION
    @node = File.exist? 'node_modules'
    @yarn = File.exist? 'yarn.lock'
    @node_version = @node ? `node --version`.chomp.sub(/^v/, '') : '16.17.0'
    @appName = @app.gsub('-', '_').camelcase(:lower)
    @org = Fly::Machines.org

    template 'Dockerfile.erb', 'Dockerfile'
    template 'dockerignore.erb', '.dockerignore'
    template 'main.tf.erb', 'main.tf'
    template 'fly.rake.erb', 'lib/tasks/fly.rake'

    credentials = nil
    if File.exist? 'config/credentials/production.key'
      credentials = 'config/credentials/production.key'
    elsif File.exist? 'config/master.key'
      credentials = 'config/master.key'
    end

    if credentials
      say_status :run, "flyctl secrets set RAILS_MASTER_KEY from #{credentials}"
      system "flyctl secrets set RAILS_MASTER_KEY=#{IO.read(credentials).chomp}"
      puts
    end

    ENV['FLY_API_TOKEN'] = `flyctl auth token`
    tee 'terraform init'
  end
end

