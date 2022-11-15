$:.unshift File.expand_path('lib')
require 'fly.io-rails/actions'

require 'bundler'
require 'pp'

def check_git
  return if Dir.exist? '/srv/fly.io-rails/lib'

  spec = Bundler::Definition.build('Gemfile', nil, []).dependencies.
  find {|spec| spec.name == 'fly.io-rails'}

  if spec.git
    if `which git`.empty? and File.exist? '/etc/debian_version'
      system 'apt-get update'
      system 'apt-get install -y git'
    end

    system `git clone --depth 1 #{spec.git} /srv/fly.io-rails`
    exit 1 unless Dir.exist? '/srv/fly.io-rails/lib'
    exec "ruby -r /srv/fly.io-rails/deploy -e #{caller_locations(1,1)[0].label}"
  end
end

def dump_config
  action = Fly::Actions.new

  config = {}
  action.instance_variables.sort.each do |name|
    config[name] = action.instance_variable_get(name)
  end

  File.open('/srv/config', 'w') {|file| PP.pp(config, file)}
end

def build_gems
  check_git
  dump_config

  system 'rake -f lib/tasks/fly.rake fly:build_gems'
end