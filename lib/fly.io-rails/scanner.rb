module Fly
  module Scanner
    # scan for major features - things that if present will likely affect
    # more than one artifact that is generated.
    def scan_rails_app
      database = YAML.load_file('config/database.yml').
        dig('production', 'adapter') rescue nil

      if database == 'sqlite3'
        @sqlite3 = true
      elsif database == 'postgresql'
        @postgresql = true
      end

      @sidekiq = IO.read('Gemfile').include? 'sidekiq' rescue false

      @cable = ! Dir['app/channels/*.rb'].empty?

      if (YAML.load_file('config/cable.yml').dig('production', 'adapter') rescue false)
        @redis_cable = @cable
      end

      if (IO.read('config/environments/production.rb') =~ /redis/i rescue false)
        @redis_cache = true
      end

      @redis = @redis_cable || @redis_cache || @sidekiq
    end
  end
end
