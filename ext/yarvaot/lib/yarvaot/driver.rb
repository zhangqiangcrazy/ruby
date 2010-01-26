#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

require 'optparse'
require 'rbconfig'

# Polymorphic to other ordinal files.
def STDIN.path
	'-'
end

# an abstract class that defines some utilities.
class YARVAOT::Subcommand
	# Used in the help string
	def self.name_to_display
		a = self.to_s.split %r/::/
		a.last.upcase
	end

	def initialize
		@verbose = false
		@sink    = nil
		@exec    = Array.new
		@opt     = OptionParser.new self.class.name_to_display + ' OPTIONS:', 30
	end

	def to_s
		@opt.to_s
	end

	def consume argv
		# argv must be  destructively modified not to propagate  known options to
		# children  subcommands, so  order! should  directly be  applied  to argv
		# itself, not a copy of it.
		a = Array.new
		begin
			@opt.parse! argv
		rescue OptionParser::InvalidOption => e
			# pass unknown options
			e.recover a
			retry
		else
			argv[0, 0] = a
		end
	end

	def run f, i
		# should be overridden by subclasses
		f
	end

	private

	# run in parallel
	def run_in_pipe f
		g = IO.popen '-', 'rb'
		if g
			f.close
			return g
		else
			begin
				yield g
			ensure
				Process.exit
			end
		end
	end

	def as_tr_cpp nam
		q = nam.dup
		q.gsub! /\s/m, '_'
		q.gsub! /[^a-zA-Z0-9_]/ do |m|
			sprintf '%08b', m.ord
		end
		q[0, 0] = 'q_' if /\d/ =~ q
		q
	end

	def verbose_out fmt, *va_list
		STDERR.printf fmt.chomp << "\n", *va_list if $VERBOSE
	end

	# Generic IO redirection
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
end

# This is the compiler driver.
class YARVAOT::Driver < YARVAOT::Subcommand

	# Used in the help string
	def self.name_to_display
		'OVERALL'
	end

	# Instantiate.  Does nothing yet.
	def initialize
		super

		@arg0         = $0
		@stop_after   = nil
		@subcommands  = {
			preprocessor: YARVAOT::Preprocessor.new,
			compiler:     YARVAOT::Compiler.new, 
			assembler:    YARVAOT::Assembler.new, 
			linker:       YARVAOT::Linker.new
		}

		objext = ::RbConfig::CONFIG["OBJEXT"]
		exeext = ::RbConfig::CONFIG["EXEEXT"]
		exeext = 'out' if exeext.empty?

		@opt.on '-E', '--stop-after-preprocess', <<-'begin'.strip do
                                   Just do preprocess, do not link.  The output
                                   is in the form of preprocessed ruby script.
		begin
			@stop_after = :preprocessor
		end

		@opt.on '-c', '--stop-after-compile', <<-'begin'.strip do
                                   Preprocess and compile the input, but do not
                                   assemble.  The  output is  in the form  of C
                                   language.
		begin
			@stop_after = :compiler
		end

		@opt.on '-S', '--stop-after-assemble', <<-'begin'.strip do
                                   Compile and  assemble the input,  but do not
                                   link.  The  output is in  the form of  a ma-
                                   chine native  object file, e.g.   an ELF ob-
                                   ject.
		begin
			@stop_after = :assembler
		end

		# no --stop-after-linker, because that's the default.

		@opt.on '-o', '--output=FILE', <<-"begin".strip do |optarg|
                                   Output to  a file  named FILE, instead  of a
                                   default sink.  Without this option a default
                                   data sink for an executable file is `a.#{exeext}',
                                   for an assembled object is `SOURCE.#{objext}', for a
                                   compiled  assembler code is  `SOURCE.c', and
                                   for  a  preprocessed   ruby  script  is  the
                                   standard output.
		begin
			@sink = optarg
		end

		@opt.on_tail '--metadebug', <<-'begin'.strip do
                                   Sets $DEBUG of  this compiler suite, not for
                                   the ruby script  to compile.  This is useful
                                   when you debug the suite.
		begin
			$DEBUG = 1
		end

		@opt.on_tail '--metaverbose', <<-'begin'.strip do
                                   Compiler  gets  annoying.  Sets $VERBOSE  of
                                   this compiler suite, not for the ruby script
                                   to compile.   This is useful  when you debug
                                   the suite.
		begin
			$VERBOSE = true
			STDERR.puts RUBY_DESCRIPTION
		end

		@opt.on_tail '-r', '--require=FEATURE', <<-"begin".strip do |optarg|
                                   Requires a  feature FEATURE, just  like ruby
                                   itself.  This is  mainly for debugging (-rpp
                                   or something).
		begin
			# FIXME: This should propagate to preprocessor
			require optarg
		end

		@opt.on_tail '-e', '--execute=STRING', <<-"begin".strip do |optarg|
                                   Instead of reading from  a file or a pipe or
                                   a  socket  or  something, just  compile  the
                                   given STRING.  Can be handy.
		begin
			@exec.push optarg
		end

		@opt.on_tail '-h', '--help', 'This is it.' do
			puts <<'HDR1', <<"HDR2", self, *@subcommands.values
                  __  _____    ____ _    _____   ____  ______
                  \ \/ /   |  / __ \ |  / /   | / __ \/_  __/
                   \  / /| | / /_/ / | / / /| |/ / / / / /
                   / / ___ |/ _, _/| |/ / ___ / /_/ / / /
                  /_/_/  |_/_/ |_| |___/_/  |_\____/ /_/

       YARVAOT: a Ruby to C (and then, to machine executable) compiler.

HDR1
SYNOPSIS:

    #@arg0 [OPTS ...] [SUBCMD [OPTS ...]] SOURCE.rb

  where SUBCMD can be one of:

    preprocess                     Preprocess  a  ruby  code  to  do  necessary
                                   transforms  and higher-level  analysis, then
                                   output a transformed ruby script.
    compile                        Compile a  ruby code into a C  code that can
                                   then  be processed  by  a system-provided  C
                                   compiler.
    assemble                       This is  a wrapper to a  C compiler.  Gener-
                                   ates  a assembler-output machine  binary ob-
                                   ject from  a C source code  generated by the
                                   above compiler subcommand.
    link                           Links  every necessary libraries  and assem-
                                   bler outputs into  a single executable file,
                                   or a single ruby extension library.

HDR2
			Process.exit
		end
	end

	# actually drive subcommands
	def start arg0, argv
		@arg0 = arg0
		consume argv
		@subcommands.each_value do |i|
			i.consume argv
		end
		@opt.parse! argv			  # force optoinparser to raise error
		verbose_out 'driver started.'

		who = case target = argv.shift
				when /^preprocess(or)?$/ then @subcommands[:preprocessor]
				when /^compiler?$/       then @subcommands[:compiler]
				when /^assembler?$/      then @subcommands[:assembler]
				when /^link(er)?$/       then @subcommands[:linker]
				else                   self
				end
		target = argv.shift if who != self
		# opening input file here, preventing outer-process attackers to choke
		# our filesystem.
		if @exec.empty?
			target ||= '-'
			fin = case target
					when '-'
						STDIN
					when String
						File.open target, 'rb'
					else
						raise TypeError, target.inspect
					end
		else
			require 'stringio'
			str = @exec.join "\n"
			fin = StringIO.new str
			target = '-e'
		end
		verbose_out 'driver opened input file %s.', target
		fout = who.run fin, target
		sink = compute_sink target
		redirect fout => sink
		if who == @subcommands[:linker] or @stop_after.nil?
			# a.out should be executable
			File.chmod 0755, sink if sink.kind_of? File
		end
	end

	def run f, n
		verbose_out 'driver entered in-order mode.'
		@subcommands.each_pair do |k, v|
			verbose_out "driver runs #{k}"
			f = v.run f, n
			return f if @stop_after == k
		end
		return f
	end

	private

	def compute_sink target
		sink = nil
		extname = nil
		basename = nil
		if @sink
			# case 1; having @sink.  Take it.
			return STDOUT if @sink == '-'
			sink = @sink
		elsif target
			# case  2; explicit input  file. Take  a basename  from it,  compute a
			# extname.
			basename = File.basename target, '.rb'
		else
			# case 3; read from STDIN.  Take "STDIN" as a basename.
			basename = "STDIN"
		end
		unless sink
			# extname calculation.
			extname = case @stop_after
						 when :preprocessor then return STDOUT
						 when :compiler     then 'c'
						 when :assembler    then ::RbConfig::CONFIG["OBJEXT"]
						 else
							 # generate a.out or whatever
							 basename = 'a'
							 extname = ::RbConfig::CONFIG["EXEEXT"]
							 extname = 'out' if extname.empty?
						 end
			sink = sprintf "%s.%s", basename, extname
		end
		verbose_out 'driver opens output file %s', sink
		return open sink, 'wb'
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
