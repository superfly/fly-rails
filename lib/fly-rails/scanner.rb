module Fly
  module Scanner
    # scan for major features - things that if present will likely affect
    # more than one artifact that is generated.
    def scan_rails_app

      ### database ###

      database = YAML.load_file('config/database.yml').
        dig('production', 'adapter') rescue nil

      if database == 'sqlite3'
        @sqlite3 = true
      elsif database == 'postgresql'
        @postgresql = true
      elsif database == 'mysql' or database == 'mysql2'
        @mysql = true
      end

      ### ruby gems ###

      @gemfile = []

      if File.exist? 'Gemfile.lock'
        parser = Bundler::LockfileParser.new(Bundler.read_file('Gemfile.lock'))
        @gemfile += parser.specs.map { |spec, version| spec.name }
      end
      
      if File.exist? 'Gemfile'
        @gemfile += Bundler::Definition.build('Gemfile', nil, []).dependencies.map(&:name)
      end

      @sidekiq = @gemfile.include? 'sidekiq'
      @anycable = @gemfile.include? 'anycable-rails'
      @rmagick = @gemfile.include? 'rmagick'
      @image_processing = @gemfile.include? 'image_processing'
      @bootstrap = @gemfile.include? 'bootstrap'
      @puppeteer = @gemfile.include? 'puppeteer'

      ### node modules ###

      @package_json = []

      if File.exist? 'package.json'
        @package_json += JSON.load_file('package.json')['dependencies'].keys rescue []
      end

      @puppeteer ||= @package_json.include? 'puppeteer'

      ### cable/redis ###

      @cable = ! Dir['app/channels/*.rb'].empty?

      if @cable
        @redis_cable = true
        if (YAML.load_file('config/cable.yml').dig('production', 'adapter') rescue '').include? 'any_cable'
          @anycable = true
        end
      end

      if (IO.read('config/environments/production.rb') =~ /redis/i rescue false)
        @redis_cache = true
      end

      @redis = @redis_cable || @redis_cache || @sidekiq

      ### api-only ###

      @api = Rails.application.config.api_only
    end
  end
end
