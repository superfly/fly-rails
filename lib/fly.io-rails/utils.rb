require 'open3'

module FlyIoRails
  module Utils

    def tee cmd
      say_status :run, cmd
      FlyIoRails::Utils.tee cmd
    end
    
    def self.tee cmd
      data = {:out => [], :err => []}

      Open3.popen3(cmd) do |stdin, stdout, stderr, thread|
	{ out: stdout, err: stderr }.each do |key, stream|
	  Thread.new do
	    until (raw_line = stream.gets).nil? do
	      data[key].push raw_line
	      
	      if key == :out
		STDOUT.print raw_line
	      else
		STDERR.print raw_line
	      end
	    end
	  end
	end

	thread.join
      end

      [data[:out].join, data[:err].join]
    end

  end
end
