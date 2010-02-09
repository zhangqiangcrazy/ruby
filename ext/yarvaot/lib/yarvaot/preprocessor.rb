#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

# This might be one of the  biggest Ripper application written so far ...  that
# extension totally lacks documentations  (especially those written in English)
# so it is  almost impossible for third parties to  manipulate ruby parse tree.
# Feel free to take a look at the codes below and learn what's going on.
require 'ripper'
require 'uuid'

# This is the preprocessor, ruby -> ruby transformation engine.
#
# Once upon a  time when there was  no Ripper, this kind of  product was almost
# impossible.  The  author of this class  want to acknowledge  Minero Aoki, the
# author of Ripper, for his great work.
class YARVAOT::Preprocessor < YARVAOT::Subcommand

	# Obfuscator namespace
	Namespace = UUID.parse "urn:uuid:182f10b8-0e42-11df-b3b6-cb6300000000"

	# Instantiate.  Does nothing yet.
	def initialize
		super
		@simulated_load_path = $LOAD_PATH.dup
		@obfuscate = false
		@ahead_of_time_require = false
		@terminals = nil
		@nonterminals = nil

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

	attr_reader :terminals, :nonterminals

	# Run.  Eat the file, do necessary conversions, then return a new file.
	#
	# One thing to  note is that this method invokes a  process inside because a
	# pipe can  occasionally stop up  and may blocks  the whole thing.   You can
	# detect the liveness of that internal child process by testing the EOF flag
	# of a returing file.
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
			@terminals.each do |i| g.write i.token end
			# Ripper do not  read towards __END__, and f  remains open to continue
			# reading  from it on  those cases.   That should  be appended  to our
			# output.
			redirect f => g
			verbose_out 'preprocessor finished.'
		end
	end

	private

	# Kernel.require needs special care in this phase...
	def recursive_require_resolution
		raise NotImplementedError, "to be written"
		@nonterminals.each do |i|
			if i.symbol == :command and i.children[0].token == "require"
				p i
			end
		end
	end

	# Does   the  token  obfuscation.    Currently  methods,   local  variables,
	# constants, class variables, instance  variables, global variables, as well
	# as comment lines are subject to scramble.
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
			y = Namespace.new_sha1 x.token
			z = y.guid.gsub '-', '_'
			w = x.token.intern
			case x.symbol
			when :ident
				x.token.replace "i" << z unless i[w]
			when :const
				x.token.replace "K" << z unless k[w]
			when :cvar
				x.token.replace "@@c" << z unless c[w]
			when :ivar
				x.token.replace "@i" << z
			when :gvar
				x.token.replace "$g" << z unless g[w]
			when :comment
				x.token.replace "# " << z << "\n"
			end
			if z != x.token
				verbose_out "preprocessor obfuscation mapping %s => %s", z, x.token
			end
		end
	end
end

# You know, Ripper is  a kind of event-driven AST visitor like  SAX in XML.  So
# when you  do a program  transformation you need  to catch every  single event
# that it emits.  EVERYTHING.  Or you  would lose data.  How to achieve that is
# not documented  even in Japanese, but  when you read  the implementation, you
# can conclude that
# - those event emitted from lexer are listed in SCANNER_EVENT_TABLE
# - those event emitted from parser are listed in PARSER_EVENT_TABLE
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

	# Parses the  given input  file (passed to  #initialize) and  generates AST.
	# The return values are a set of terminal symbols, and a tree of nonterminal
	# symbols.
	def parse
		@terminals = Array.new
		nonterminals = super
		terminals, @terminals = @terminals, nil
	end

	Ripper::SCANNER_EVENT_TABLE.each do |(e, f)|
		define_method 'on_' + e.to_s do |tok|
			ret = Terminal.new lineno, column, e, tok
			@terminals.push ret
			ret
		end
	end

	Ripper::PARSER_EVENT_TABLE.each do |(e, f)|
		f = 'on_' + e.to_s
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
