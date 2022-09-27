require 'pty'

module FlyIoRails
  module Utils

    def tee cmd
      say_status :run, cmd if defined? say_status
      FlyIoRails::Utils.tee cmd
    end
    
    def self.tee cmd
      data = []

      begin
        PTY.spawn( cmd ) do |stdin, stdout, pid|
          begin
            # Do stuff with the output here. Just printing to show it works
            stdin.each do |line| 
              print line
              data << line
            end
          rescue Errno::EIO
          end
        end
      rescue PTY::ChildExited
      end

      data.join
    end

    def create_app(name: nil, org: 'personal', regions: [], nomad: false, **rest)
      cmd = if name
        "flyctl apps create #{name.inspect} --org #{org.inspect} --machines"
      else
        "flyctl apps create --generate-name --org #{org.inspect} --machines"
      end

      cmd.sub! ' --machines', '' if nomad
  
      output = tee cmd
      exit 1 unless output =~ /^New app created: /
  
      @app = output.split.last
  
      unless regions.empty?
        @regions = regions.flatten
      end

      @app
    end
  end
end
