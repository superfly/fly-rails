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

  end
end
