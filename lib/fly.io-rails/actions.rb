require 'thor'
require 'active_support'
require 'active_support/core_ext/string/inflections'
require 'fly.io-rails/machines'

module Fly
  class Actions < Thor::Group
    include Thor::Actions
    include Thor::Base
    attr_accessor :options

    def initialize(app = nil)
      self.app = app if app

      @ruby_version = RUBY_VERSION
      @bundler_version = Bundler::VERSION
      @node = File.exist? 'node_modules'
      @yarn = File.exist? 'yarn.lock'
      @node_version = @node ? `node --version`.chomp.sub(/^v/, '') : '16.17.0'
      @org = Fly::Machines.org
      @regions = []

      @options = {}
      @destination_stack = [Dir.pwd]
    end

    def app
      return @app if @app
      self.app = TOML.load_file('fly.toml')['app']
    end

    def app=(app)
      @app = app
      @appName = @app.gsub('-', '_').camelcase(:lower)
    end

    source_paths.push File::expand_path('../generators/templates', __dir__)

    def generate_dockerfile
      app
      template 'Dockerfile.erb', 'Dockerfile'
    end

    def generate_dockerignore
      app
      template 'dockerignore.erb', '.dockerignore'
    end

    def generate_terraform
      app
      template 'main.tf.erb', 'main.tf'
    end

    def generate_raketask
      app
      template 'fly.rake.erb', 'lib/tasks/fly.rake'
    end

    def generate_all
      generate_dockerfile
      generate_dockerignore
      generate_terraform
      generate_raketask
    end
  end
end
