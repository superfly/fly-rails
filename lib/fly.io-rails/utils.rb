require 'pty'

module FlyIoRails
  module Utils

    def tee cmd
      say_status :run, cmd
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

    def create_app(name=nil, org='personal', regions=[])
      cmd = if name
        "flyctl apps create #{name.inspect} --org #{org.inspect}"
      else
        "flyctl apps create --generate-name --org #{org.inspect}"
      end
  
      output = tee cmd
      exit 1 unless output =~ /^New app created: /
  
      @app = output.split.last
      template 'fly.toml.erb', 'fly.toml'
  
      if regions.empty?
        @regions = JSON.parse(`flyctl regions list --json`)['Regions'].
          map {|region| region['Code']}
      else
        @regions = regions.flatten
      end

      @region = @regions.first || 'iad'
    end
  end
end
