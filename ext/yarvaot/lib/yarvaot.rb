#! /some/path/to/ruby
# coding=utf-8
# :main: YARVAOT::Driver

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

require 'yarvaot.so'
require 'tempfile'

# An  abstract class  that  represents a  compiler  subprocess.  Some  instance
# methods _must_ be  overridden because this class does  not define real useful
# things for them.
#
# A  compiler's  subprocess  is much  like  a  UNIX  filter program.   It  eats
# something from its standard input,  does some conversion, and then woops that
# to its standard output.  This series  of behaviour is kicked from whose "run"
# method.
class YARVAOT::Subcommand

	# Used in the help string
	def self.name_to_display
		a = self.to_s.split '::'
		a.last.upcase
	end

	# Also used in the help string
	def to_s
		"\n" << @opt.to_s
	end

	# Like  I wrote  above, a  subprocess is  a pseudo  UNIX filter.   so  it is
	# natural for a subprocess to have its own command-line options.  A subclass
	# of it should override #initialize and  call super at the very beginning of
	# it.
	def initialize
		@opt = OptionParser.new self.class.name_to_display + ' OPTIONS:', 30
	end

	# A process argument vector _argv_  is parsed here.  A subprocess should eat
	# its command and ignore everything else.
	def consume argv
		# Argv  must  be  destructively  modified  not to  propagate  options  to
		# children  subcommands, so  parse! should  directly be  applied  to argv
		# itself, not a copy of it.
		a = Array.new
		begin
			@opt.parse! argv
		rescue OptionParser::InvalidOption => e
			# unknown options
			e.recover a
			retry
		else
			argv[0, 0] = a
		end
	end

	# This is the main method, but  does nothing on this class itself. should be
	# overridden by subclasses.
	def run f, n
		return f
	end

	private

	# Makes an identifier string corresponding to  _name_, which is safe for a C
	# compiler.   The   name  as_tr_cpp  was   taken  from  a   autoconf  macro,
	# AS_TR_CPP().
	def as_tr_cpp name, prefix = 'q_'
		q = name.dup
		q.force_encoding 'ASCII-8BIT'
		q.gsub! %r/\s/m, '_'
		q.gsub! %r/[^a-zA-Z0-9_]/, '_'
		q.gsub! %r/_+/, '_'
		q[0, 0] = prefix if /\A\d/ =~ q
		q
	end

	# For debug.
	#
	# fmt:: format string
	# va_list:: variadic argument vector
	def verbose_out fmt, *va_list
		STDERR.printf fmt.chomp << "\n", *va_list if $VERBOSE
	end

	# Generic IO  redirection.  This is  needed because a subprocess  itself can
	# occasionally spawn a child process,  such as a C compiler.  IO redirection
	# is  done  as much  as  possible in  Process.spawn,  but  some cases  needs
	# explicit redirection business.
	#
	# h:: a set of IO -> IO mapping
	def redirect h
		buf = String.new
		h.each_pair do |from, to|
			begin
				while from.readpartial 32768, buf
					j = to.write buf
					raise Errno::EPIPE if j != buf.length
				end
			rescue EOFError
			end
		end
	end

	# Actually runs in a pipe, by either forking itself via popen, or by pipe(2)
	# with Ruby threads.  Yields and then returns a pipe, which is an output.
	def run_in_pipe input # :yields: output
		output = IO.popen '-', 'rb'
	rescue NotImplementedError
		begin
			r, w = IO.pipe
		rescue NotImplementedError
			# no way
			Process.abort "no way to spawn a C compiler"
		else
			# no fork but a pipe: emulate using threads
			Thread.start do
				begin
					Thread.pass
					yield w
				ensure
					w.close
				end
			end
			return r
		end
	else
		# in case of fork-supported environments
		if output
			input.close
			return output
		else
			begin
				yield STDOUT
			rescue Exception => e
				STDERR.puts e.message
				STDERR.puts e.backtrace
				Process.abort
			else
				Process.exit
			end
		end
	end

	# Creates a  temporary file  and uses it  as a  data sink.  It  is sometimes
	# necessary, namely when you fork a gcc, which requires a seekable output.
	def run_in_tempfile name # :yields: tempfile
		b = canonname name
		b << '.'
		output = Tempfile.new b
		yield output
		return output
	end

	# A  canonical name  of a  file is  what Ruby  thinks that  file  is...  For
	# instance,  a  file /some/load/path/to/foo.rb  is  required  by ruby  using
	# ``require "foo"'', so its canonical name is foo.
	def canonname name
		tmp = File.basename name, '.*'
		as_tr_cpp tmp
	end
end

require_relative 'yarvaot/driver'
require_relative 'yarvaot/preprocessor'
require_relative 'yarvaot/compiler'
require_relative 'yarvaot/assembler'
require_relative 'yarvaot/linker'

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
