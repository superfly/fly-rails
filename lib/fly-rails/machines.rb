require 'net/http'
require 'json'

module Fly
  # Thin wrapper over https://fly.io/docs/reference/machines/
  #
  # *** WARNING ***
  #
  # No validation or escaping is done by this code.  It is assuming that
  # the caller is trusted and does pass through unsanitized user input.
  #
  module Machines
    @@api_token = ENV['FLY_API_TOKEN']
    @@fly_api_hostname = nil

    # determine fly api hostname.  Returns nil if no proxy is running
    def self.fly_api_hostname
      return @@fly_api_hostname if @@fly_api_hostname

      Net::HTTP.get URI('http://_api.internal:4280')
      @@fly_api_hostname = '_api.internal:4280'
    rescue
      begin
        Net::HTTP.get URI('http://127.0.0.1:4280')
        @@fly_api_hostname = '127.0.0.1:4280'
      rescue
        nil
      end
    end

    # determine application's organization
    def self.org
      org = 'personal'

      if File.exist? 'fly.toml'
        require 'toml'
        app = TOML.load_file('fly.toml')['app']

        apps = JSON.parse(`flyctl list apps --json`) rescue []

        apps.each do |info|
          org = info['Organization'] if info['ID'] == app
        end
      end

      org
    end

    # determine fly api hostname.  Starts proxy if necessary
    def self.fly_api_hostname!
      hostname = fly_api_hostname
      return hostname if hostname

      pid = fork { exec "flyctl machines api-proxy --org #{org}" }
      at_exit { Process.kill "INT", pid }

      # wait up to 12.7 seconds for the proxy to start
      wait = 0.1
      6.times do
        sleep wait
        begin
          Net::HTTP.get URI('http://127.0.0.1:4280')
          @@fly_api_hostname = '127.0.0.1:4280'
          break
        rescue
          wait *= 2
        end
      end

      @@fly_api_hostname
    end

    # create_fly_application app_name: 'user-functions', org_slug: 'personal'
    def self.create_fly_application options
      post '/v1/apps', options
    end

    # get_application_details 'user-functions'
    def self.get_application_details app
      get "/v1/apps/#{app}"
    end

    # create_and_start_machine 'user-functions', name: 'quirky_machine', config: {
    #   image: 'flyio/fastify-functions',
    #   env: {'APP_ENV' => 'production'},
    #   services: [
    #     {
    #       ports: [
    #         {port: 443, handlers: ['tls', 'http']},
    #         {port: 80, handlers: ['http']}
    #       ],
    #       protocol: 'tcp',
    #       internal_protocol: 'tcp',
    #     }
    #   ]
    # }
    def self.create_and_start_machine app, options
      post "/v1/apps/#{app}/machines", options
    end

    # wait_for_machine 'user-functions', '73d8d46dbee589'
    def self.wait_for_machine app, machine, options = {timeout:60, status: 'started'}
      get "/v1/apps/#{app}/machines/#{machine}/wait?#{options.to_query}"
    end

    # get_a_machine machine 'user-functions', '73d8d46dbee589'
    def self.get_a_machine app, machine
      get "/v1/apps/#{app}/machines/#{machine}"
    end

    # update_a_machine 'user-functions', '73d8d46dbee589', config: {
    #   image: 'flyio/fastify-functions',
    #   guest: { memory_mb: 512, cpus: 2 }
    # }
    def self.update_a_machine app, machine, options
      post "/v1/apps/#{app}/machines/#{machine}", options
    end

    # stop_machine machine 'user-functions', '73d8d46dbee589'
    def self.stop_machine app, machine
      post "/v1/apps/#{app}/machines/#{machine}/stop"
    end

    # start_machine machine 'user-functions', '73d8d46dbee589'
    def self.start_machine app, machine
      post "/v1/apps/#{app}/machines/#{machine}/stop"
    end

    # delete_machine machine 'user-functions', '73d8d46dbee589'
    def self.delete_machine app, machine
      delete "/v1/apps/#{app}/machines/#{machine}"
    end

    # list_machines machine 'user-functions'
    def self.list_machines app, machine
      get "/v1/apps/#{app}/machines"
    end

    # delete_application 'user-functions'
    def self.delete_application app, force=false
      delete "/v1/apps/#{app}?force=#{force}"
    end

    # generic get
    def self.get(path)
      api(path) {|uri| request = Net::HTTP::Get.new(uri) }
    end

    # generic post
    def self.post(path, hash=nil)
      api(path) do |uri|
        request = Net::HTTP::Post.new(uri)
        request.body = hash.to_json if hash
        request
      end
    end

    # generic delete
    def self.delete(path)
      api(path) {|uri| request = Net::HTTP::Delete.new(uri) }
    end

    # graphql -- see https://til.simonwillison.net/fly/undocumented-graphql-api
    def self.graphql(query)
      api('/graphql', 'https://api.fly.io/') do |path|
        request = Net::HTTP::Post.new(path)
        request.body = { query: query }.to_json
        request
      end
    end

    # common processing for all APIs
    def self.api(path, host=nil, &make_request)
      host ||= "http://#{fly_api_hostname}"
      uri = URI.join(host, path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.set_debug_output $stderr if ENV['TRACE'] 
      http.use_ssl = true if uri.instance_of? URI::HTTPS

      request = make_request.call(uri.request_uri)

      @@api_token ||= `flyctl auth token`.chomp
      headers = {
        "Authorization" => "Bearer #{@@api_token}",
        "Content-Type" => "application/json",
        "Accept" => "application/json"
      }
      headers.each {|header, value| request[header] = value}

      response = http.request(request)

      if response.is_a? Net::HTTPSuccess
        JSON.parse response.body, symbolize_names: true
      else
        body = response.body
        begin
          error = JSON.parse(body)
        rescue
          error = {body: body}
        end

        error[:status] = response.code
        error[:message] = response.message

        error
      end
    end
  end
end
