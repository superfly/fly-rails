require 'rack'
require 'rack/handler/puma'

namespace :mock do
  desc 'Mock server - useful for debugging startup issues'
  task :server do
    handler = Rack::Handler::Puma

    class RackApp
      def call(env)
        [200, {"Content-Type" => "text/plain"}, ["Hello from Fly.io"]]
      end
    end

    handler.run RackApp.new, Port: ENV['PORT'] || 8080
  end
end
