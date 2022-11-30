require 'strscan'

module Fly
  # a very liberal HCL scanner
  module HCL
    def self.parse(string)
      result = []
      name = nil
      stack = []
      block = {}
      cursor = block
      result.push block

      hcl = StringScanner.new(string)
      until hcl.eos?
	hcl.scan(%r{\s*(\#.*|//.*|/\*[\S\s]*?\*/)*})

	if hcl.scan(/[a-zA-Z]\S*|\d[.\d]*|"[^"]*"/)
	  if cursor.is_a? Array
	    cursor.push token(hcl.matched)
	  elsif name == nil
	    name = token(hcl.matched)
	  else
	    hash = {}
	    cursor[name] = hash
	    name = token(hcl.matched)
	    cursor = hash
	  end
	elsif hcl.scan(/=/)
	  hcl.scan(/\s*/)
	  if hcl.scan(/\[/)
	    list = []
	    cursor[name] = list
            name = nil
	    stack.push cursor
	    cursor = list
	  elsif hcl.scan(/\{/)
	    hash = {}
	    cursor[name] = hash
	    name = nil
	    stack.push cursor
	    cursor = hash
	  elsif hcl.scan(/.*/)
	    cursor[name] = token(hcl.matched)
	    name = nil
	  end
	elsif hcl.scan(/\{/)
	  hash = {}
	  if cursor.is_a? Array
	    cursor << hash
	  else
	    cursor[name] = hash
	  end
	  name = nil
	  stack.push cursor
	  cursor = hash
	elsif hcl.scan(/\[/)
	  list = []
	  stack.push cursor
	  cursor = list
	elsif hcl.scan(/\}|\]/)
	  cursor = stack.pop

	  if stack.empty?
	    block = {}
	    cursor = block
	    result.push block
	  end
	elsif hcl.scan(/[,=:]/)
          nil
	elsif hcl.scan(/.*/)
          unless hcl.matched.empty?
	    STDERR.puts "unexpected input: #{hcl.matched.inspect}"
          end
	end
      end

      result.pop if result.last.empty?
      result
    end

  private
    def self.token(match)
      if match =~ /^\d/
	if match =~ /^\d+$/
	  match.to_i
	else
	  match.to_f
	end
      elsif match =~ /^\w+$/
	match.to_sym
      elsif match =~ /^"(.*)"$/
	$1
      else
	match
      end
    end
  end
end
