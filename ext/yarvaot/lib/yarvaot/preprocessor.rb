#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

# This might be one of the  biggest ripper application written so far ...  that
# extension totally lacks documentations  (especially those written in English)
# so it is  almost impossible for third parties to  manipulate ruby parse tree.
# Feel free to take a look at the codes below and learn what's going on.
require 'ripper'
require 'digest'

# This is the preprocessor, ruby->ruby transformation engine.
class YARVAOT::Preprocessor < YARVAOT::Subcommand

	# Instantiate.  Does nothing yet.
	def initialize
		super
		@simulated_load_path = $LOAD_PATH.dup
		@obfuscate = true
		@ahead_of_time_require = false

		@opt.on '-I', '--search PATH', <<-'begin'.strip do |optarg|
                                   Append (in a way like Array#push) the passed
                                   directory to $LOAD_PATH.
		begin
			@simulated_load_path.push optarg
		end

		@opt.on '--[no-]obfuscate', <<-'begin'.strip do |optarg|
                                   Enable (or disable) a obfuscation.  Normally
                                   a YARVAOT  compiler preserves as  much names
                                   as possible  -- such as  class names, module
                                   names, method names,  variable names, and so
                                   on.  Those names are visible via system pro-
                                   vided debuggers.   This option prevents that
                                   behaviour  by  smashing  those  names  using
                                   Digest::SHA512.
		begin
			@obfuscate = optarg
		end
	end

	# Run.  Eat the file, do necessary conversions, then return a new file.
	def run f, n
		run_in_pipe f do |g|
			verbose_out 'preprocessor started.'
			ripper = YARVAOT::Ripper.new f, n
			@terminals, @nonterminals = ripper.parse
			verbose_out 'preprocessor generated AST.'

			# this is the transformation
			obfuscate if @obfuscate
			recursive_require_resolution if @ahead_of_time_require
			verbose_out 'preprocessor done conversion.'

			# output
			@terminals.each do |i| STDOUT.write i.token end
			# Ripper do  not read below __END__,  and fp remains  open to continue
			# reading  from it on  those cases.   That should  be appended  to our
			# output.
			redirect f => STDOUT
			verbose_out 'preprocessor finished.'
		end
	end

	private

	def recursive_require_resolution
		raise NotImplementedError, "to be written"
		@nonterminals.each do |i|
			if i.symbol == :command and i.children[0].token == "require"
				p i
			end
		end
	end

	def obfuscate
		i = Hash.new
		k = Hash.new
		c = Hash.new
		g = Hash.new
		ObjectSpace.each_object Module do |m|
			if /YARVAOT/ !~ m.to_s
				[m.public_instance_methods,
				 m.protected_instance_methods,
				 m.private_instance_methods].each do |a|
					a.each do |v|
						i[v] = true
					end
				end
				m.constants.each do |v|
					k[v] = true
				end
				m.class_variables.each do |v|
					c[v] = true
				end
			end
			global_variables.each do |v|
				g[v] = true
			end
		end

		@terminals.each do |x|
			y = x.token.dup
			z = Digest::SHA512.hexdigest y
			case x.symbol
			when :ident
				x.token.replace "i" << z unless i[y.intern]
			when :const
				x.token.replace "K" << z unless k[y.intern]
			when :cvar
				x.token.replace "@@c" << z unless c[y.intern]
			when :ivar
				x.token.replace "@i" << z
			when :gvar
				x.token.replace "$g" << z unless g[y.intern]
			when :comment
				x.token.replace "# " << z << "\n"
			end
			if y != x.token
				verbose_out "preprocessor obfuscation mapping %s => %s", y, x.token
			end
		end
	end
end

# You know, Ripper is  a kind of event-driven AST visitor like  SAX in XML.  So
# when you  do a program  transformation you need  to catch every  single event
# that it emits.  EVERYTHING.  Or you  would lose data.  How to achieve that is
# not documented  even in Japanese, but  when you read  the implementation, you
# can conclude that
# (1) those event emitted from lexer are listed in SCANNER_EVENT_TABLE
# (2) those event emitted from parser are listed in PARSER_EVENT_TABLE
# and that's all.
class YARVAOT::Ripper < Ripper
	# A very tiny AST implementation
	AST = Struct.new :symbol, :children
	class AST
		def << i
			children << i
			self
		end
		def each
			yield self
			children.each do |i|
				i.each do |j|
					yield j
				end if i.is_a? AST
			end
			self
		end
	end

	# Terminal symbols
	Terminal = Struct.new :lineno, :column, :symbol, :token

	def parse
		@terminals = Array.new
		nonterminals = super
		terminals, @terminals = @terminals, nil
		return terminals, nonterminals
	end

	Ripper::SCANNER_EVENT_TABLE.each do |(e, f)|
		define_method 'on_' + e do |tok|
			ret = Terminal.new lineno, column, e, tok
			@terminals.push ret
			ret
		end
	end

	Ripper::PARSER_EVENT_TABLE.each do |(e, f)|
		f = 'on_' + e
		case e.to_s
		when /_add$/
			define_method f do |l, i|
				l << i
			end
		when /(.+)(_new)?$/
			ev = $1.intern
			define_method f do |*a|
				ret = AST.new ev, a
			end
		end
	end
end

# 
# Local Variables:
# mode: ruby
# coding: utf-8
# indent-tabs-mode: t
# tab-width: 3
# ruby-indent-level: 3
# fill-column: 79
# default-justification: full
# End:
# vi: ts=3 sw=3
