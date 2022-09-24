module Fly
  module DSL
    class Base
      def initialize
	@value = {}
      end

      def self.option name, default=nil
	@options ||= {}
	@options[name] = default

	define_method name do |*args|
	  if args.length == 1
	    @value[name] =  args.first
	  elsif args.length > 1
	    raise ArgumentError.new("wrong number of arguments (given #{args.length}, expected 0..1)")
	  end

	  @value.include?(name) ? @value[name] : default
	end
      end

      def self.options
	@options ||= {}
      end
    end

    #############################################################

    class Machine < Base
      option :cpus, 1
      option :cpu_kind, 'shared'
      option :memory_mb, 256
    end

    class Postgres < Base
      option :vm_size, 'shared-cpu-1x'
      option :volume_size, 1
      option :initial_cluster_size, 1
    end

    class Redis < Base
      option :plan, "Free"
    end

    class Sqlite3 < Base
      option :size, 3
    end

    #############################################################

    class Config
      @@blocks = {}

      def initialize
	@config = {}
      end

      def self.block name, kind
	@@blocks[name] = kind

	define_method name do |&block| 
	  @config[name] ||= kind.new
	  @config[name].instance_eval(&block) if block
	  @config[name]
	end
      end

      def self.blocks
	@@blocks
      end

      block :machine, Machine
      block :postgres, Postgres
      block :redis, Redis
      block :sqlite3, Sqlite3
    end
  end
end
