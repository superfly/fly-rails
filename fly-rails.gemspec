require_relative "lib/fly-rails/version"

Gem::Specification.new do |spec|
  spec.name        = "fly-rails"
  spec.version     = Fly::VERSION
  spec.authors     = [ 
    "Sam Ruby",
  ]
  spec.email       = "rubys@intertwingly.net"
  spec.homepage    = "https://github.com/rubys/fly-rails"
  spec.summary     = "Rails support for Fly-io"
  spec.license     = "Apache-2.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
  }

  spec.files = Dir["{app,lib}/**/*", "LICENSE", "Rakefile", "README.md"]
  spec.bindir = "exe"

  spec.add_dependency "toml"
end
