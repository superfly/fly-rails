require 'open3'

class TerraformGenerator < Rails::Generators::Base
  include FlyIoRails::Utils

  class_option :name, type: :string, required: false
  class_option :org, type: :string, default: 'personal'
  class_option :region, type: :array, repeatable: true, default: []

  def terraform
    cmd = if options[:name]
      "flyctl apps create #{options[:name].inspect} --org #{options[:org].inspect}"
    else
      "flyctl apps create --generate-name --org #{options[:org].inspect}"
    end

    output = tee cmd
    exit 1 unless output =~ /^New app created: /

    @app = output.split.last
    create_file 'fly.toml', "app = #{@app.inspect}\n"

    if options[:region].empty?
      @regions = JSON.parse(`flyctl regions list --json`)['Regions'].
        map {|region| region['Code']}
    else
      @regions = options[:regions].flatten
    end

    source_paths.push File.expand_path('./templates', __dir__)

    @ruby_version = RUBY_VERSION
    @bundler_version = Bundler::VERSION
    @appName = @app.gsub('-', '_').camelcase(:lower)
    template 'Dockerfile.erb', 'Dockerfile'
    template 'dockerignore.erb', '.dockerignore'
    template 'main.tf.erb', 'main.tf'
    template 'fly.rake.erb', 'lib/tasks/fly.rake'

    ENV['FLY_API_TOKEN'] = `flyctl auth token`
    tee 'terraform init'
  end
end

