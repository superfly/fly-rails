require_relative "lib/fly.io-rails/version"

Gem::Specification.new do |spec|
  spec.name        = "fly.io-rails"
  spec.version     = Fly_io::VERSION
  spec.authors     = [ 
    "Sam Ruby",
  ]
  spec.email       = "rubys@intertwingly.net"
  spec.homepage    = "https://github.com/rubys/fly-io.rails"
  spec.summary     = "Rails support for Fly-io"
  spec.license     = "Apache-2.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
  }

  spec.files = Dir["{app,lib}/**/*", "LICENSE", "Rakefile", "README.md"]
  spec.bindir = "exe"
  spec.executables << "flyctl"

  spec.add_dependency "fly-ruby"
  spec.add_dependency "toml"
end
