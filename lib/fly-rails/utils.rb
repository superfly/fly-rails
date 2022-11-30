begin
  require 'pty'
rescue LoadError
  # Presumably Windows
end

module FlyIoRails
  module Utils

    def tee cmd
      say_status :run, cmd if defined? say_status
      FlyIoRails::Utils.tee cmd
    end
    
    def self.tee cmd
      data = []

      if defined? PTY
        begin
          # PTY supports ANSI cursor control and colors
          PTY.spawn(cmd) do |read, write, pid|
            begin
              read.each do |line|
                print line
                data << line
              end
            rescue Errno::EIO
            end
          end
        rescue PTY::ChildExited
        end
      else
        # no support for ANSI cursor control and colors
        Open3.popen2e(cmd) do |stdin, out, thread|
          out.each do |line|
            print line
            data << line
          end
        end
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
