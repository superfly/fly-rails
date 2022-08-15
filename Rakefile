# coding: utf-8
#
#  Rake tasks to manage native gem packages with flyctl binary executables from github
#
#  TL;DR: run "rake package"
#
#  The native platform gems (defined by Fly_io::PLATFORMS)
#  will each contain two files in addition to what the vanilla ruby gem contains:
#
#     exe/
#     ├── flyctl                                 #  generic ruby script to find and run the binary
#     └── <Gem::Platform architecture name>/
#         └── flyctl                             #  the flyctl binary executable
#
#  The ruby script `exe/flyctl` is installed into the user's path, and it simply locates the
#  binary and executes it. Note that this script is required because rubygems requires that
#  executables declared in a gemspec must be Ruby scripts.
#
#  As a concrete example, an x86_64-linux system will see these files on disk after installing
#  fly.io-rails-1.x.x-x86_64-linux.gem:
#
#     exe/
#     ├── flyctl     
#     └── x86_64-linux/
#         └── flyctl     
#
#  So the full set of gem files created will be:
#
#  - pkg/fly.io-rails-1.0.0.gem
#  - pkg/fly.io-rails-1.0.0-arm64-darwin.gem
#  - pkg/fly.io-rails-1.0.0-x64-mingw32.gem
#  - pkg/fly.io-rails-1.0.0-x86_64-darwin.gem
#  - pkg/fly.io-rails-1.0.0-x86_64-linux.gem
# 
#  Note that in addition to the native gems, a vanilla "ruby" gem will also be created without
#  either the `exe/flyctl` script or a binary executable present.
#
#
#  New rake tasks created:
#
#  - rake gem:ruby           # Build the ruby gem
#  - rake gem:arm64-darwin   # Build the arm64-darwin gem
#  - rake gem:x64-mingw32    # Build the x64-mingw32 gem
#  - rake gem:x86_64-darwin  # Build the x86_64-darwin gem
#  - rake gem:x86_64-linux   # Build the x86_64-linux gem
#  - rake download           # Download all flyctl binaries
#
#  Modified rake tasks:
#
#  - rake gem                # Build all the gem files
#  - rake package            # Build all the gem files (same as `gem`)
#  - rake repackage          # Force a rebuild of all the gem files
#
#  Note also that the binary executables will be lazily downloaded when needed, but you can
#  explicitly download them with the `rake download` command.
#
require "bundler/setup"
require "bundler/gem_tasks"
require "rubygems/package_task"
require 'net/http'
require 'json'
require 'stringio'
require 'zip'
require_relative 'lib/fly.io-rails/platforms'

task default: :package

FLY_IO_RAILS_GEMSPEC = Bundler.load_gemspec("fly.io-rails.gemspec")

gem_path = Gem::PackageTask.new(FLY_IO_RAILS_GEMSPEC).define
desc "Build the ruby gem"
task "gem:ruby" => [gem_path]

def fetch(uri, limit = 10)
  raise ArgumentError, 'HTTP redirect too deep' unless limit > 0
  response = Net::HTTP.get_response(URI(uri))

  case response
  when Net::HTTPSuccess
    response.body
  when Net::HTTPRedirection
    fetch(response['location'], limit - 1)
  else
    STDERR.puts 'HTTP Error: ' + response.message.to_s
    exit 1
  end
end

exepaths = []
uri = 'https://api.github.com/repos/superfly/flyctl/releases/latest'
release = JSON.parse(fetch(uri))

release['assets'].each do |asset|
  platform = Fly_io::PLATFORMS[asset['name'][/^flyctl_.*?_(.*?)\./, 1]]
  next unless platform

  FLY_IO_RAILS_GEMSPEC.dup.tap do |gemspec|
    exedir = File.join(gemspec.bindir, platform) # "exe/x86_64-linux"
    exepath = File.join(exedir, "flyctl") # "exe/x86_64-linux/flyctl"

    if asset['name'] =~ /Windows/i
      exepath += '.exe' 
      dll = File.join(exedir, 'wintun.dll')
      gemspec.files << dll
      file dll => exepath
    end

    exepaths << exepath
    gemspec.files << exepath

    # modify a copy of the gemspec to include the native executable
    gemspec.platform = platform

    # create a package task
    gem_path = Gem::PackageTask.new(gemspec).define
    desc "Build the #{platform} gem"
    task "gem:#{platform}" => [gem_path]

    directory exedir
    file exepath => [exedir] do
      release_url = asset['browser_download_url']
      warn "Downloading #{release_url} ..."

      case File.extname(asset['name'])
      when '.gz'
	Zlib::GzipReader.wrap(StringIO.new(fetch(release_url))) do |gz|
	  Gem::Package::TarReader.new(gz) do |tar|
	    tar.each do |entry|
              exepath = File.join(exedir, entry.full_name)
              File.open(exepath, "wb") do |local|
                local.write(entry.read)
              end
              FileUtils.chmod(0755, exepath, verbose: true)
	    end
	  end
	end
      when '.zip'
	Zip::File.open_buffer(fetch(release_url)) do |zip_file|
	  zip_file.each do |entry|
            exepath = File.join(exedir, entry.name)
            STDERR.puts exepath
            File.open(exepath, "wb") do |local|
              local.write(zip_file.read(entry.name))
            end
	  end
	end
      end
    end
  end
end

desc "Download all flyctl binaries"
task download: exepaths

task package: :download

CLOBBER.add(exepaths.map { |path| File.dirname(path) })

