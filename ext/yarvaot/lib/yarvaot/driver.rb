#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

require 'optparse'
require 'rbconfig'

# This is the compiler driver.
#
# A compiler  driver is a supervisor  process to run  necessary subprocesses to
# convert its input into a necessary output form.  For a implementation matter,
# Driver class itself is a subclass of Subcommand class.
#
# This driver takes a bunch of command line options.  Take a look at its --help
# to see the complete list of them.  And tell me how if you know there is a way
# *not* to display everything on --help, it's too long now...
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
		@evalary      = Array.new
		@exec         = false
		@sink         = nil
		@save_temps   = false
		@subcommands  = { # order maters here
			nil =>        self,
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

		@opt.on '-S', '--stop-after-compile', <<-'begin'.strip do
                                   Preprocess and compile the input, but do not
                                   assemble.  The  output is  in the form  of C
                                   language.
		begin
			@stop_after = :compiler
		end

		@opt.on '-c', '--stop-after-assemble', <<-'begin'.strip do
                                   Compile and  assemble the input,  but do not
                                   link.  The  output is in  the form of  a ma-
                                   chine native  object file, e.g.   an ELF ob-
                                   ject.
		begin
			@stop_after = :assembler
		end

		# no --stop-after-linker, because that's the default.

		@opt.on '-x', '--execute', <<-'begin'.strip do
                                   Instead of creating an executable file, just
                                   execute the compiled output.  This is mainly
                                   for debugging  (through replacing RUBY envi-
                                   ronment  variable).   This  option not  only
                                   overrides all the --stop-after-* series com-
                                   mand  line   options,  but  also   make  the
                                   compiler  pass  every  unknown command  line
                                   options to the execution.  This option alone
                                   does  not  leave  any  single  file  on  the
                                   filesystem  so   if  you  need  intermediate
                                   products, specify --save-temps with it.
		begin
			@exec = true
		end

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

		@opt.on '--[no-]save-temps', <<-'begin'.strip, TrueClass do |optarg|
                                   Save  temporary files  between  each stages.
                                   Without this  option stages are  totally run
                                   in pipes, so if you want to debug your a.out
                                   with  debuggers, you  would better  set this
                                   option, otherwise  debugger breakpoints gets
                                   totally out of use.
		begin
			@save_temps = optarg
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

		@opt.on_tail '-W[n]', <<-'begin'.strip, Integer do |optarg|
                                   Not yet.
		begin
			# Not yet.
		end

		@opt.on_tail '-r', '--require=FEATURE', <<-'begin'.strip do |optarg|
                                   Requires a  feature FEATURE, just  like ruby
                                   itself.  This is  mainly for debugging (-rpp
                                   or something).
		begin
			# FIXME: This should propagate to preprocessor
			require optarg
		end

		@opt.on_tail '-e', '--eval=STRING', <<-'begin'.strip do |optarg|
                                   Instead of reading from  a file or a pipe or
                                   a  socket  or  something, just  compile  the
                                   given STRING.  Can be handy.
		begin
			@evalary.push optarg
		end

		@opt.on_tail '-h', '--help', 'This is it.' do
			pager_out <<'HDR1', <<"HDR2", *@subcommands.values
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

	# This is the entry point.  Invokes each subcommands up to what _argv_ says.
	#
	# _arg0_:: Process instance name, normally $0
	# _argv_:: Process argument vector, normally ARGV
	def start arg0, argv
		@arg0 = arg0

		# argv handling
		consume argv
		@subcommands.each_value do |i|
			i.consume argv
		end
		if @exec
			who = self
			target = argv.shift
		else
			@opt.parse! argv		  # force optoinparser to raise error

			# determine who and what to deal with.
			who = case target = argv.shift
					when /^preprocess(or)?$/ then @subcommands[:preprocessor]
					when /^compiler?$/       then @subcommands[:compiler]
					when /^assembler?$/      then @subcommands[:assembler]
					when /^link(er)?$/       then @subcommands[:linker]
					else                          self
					end
			target = argv.shift if who != self
		end
		verbose_out 'driver started.'
		# opening input  file here,  preventing outer-process attackers  to choke
		# our filesystem.
		if @evalary.empty?
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
			str = @evalary.join "\n"
			fin = StringIO.new str
			target = '-e'
		end
		verbose_out 'driver opened input file %s.', target

		# This is the part that actually does compilations.
		fout, = who.run fin, target
		if @save_temps # in that case already done.
			sink = fout
		else
			sink = compute_sink who, target
			redirect fout => sink 
		end

		# a.out should be executable.
		if who == @subcommands[:linker] or (who == self and @stop_after.nil?)
			File.chmod 0755, sink if sink.kind_of? File
		end

		if @exec
			raise <<-end unless sink.is_a? File

Cannot  execute a  pipe.  If  you  are using  Linux that  is actually  possible
through fexecve(3), but  that functionality is not implemented  to Ruby, so you
have to specify a real filename rather  than "-", or do not specify anything --
in that case a canonical filename e.g. a.out is used.
			end
			begin
				path = File.realpath sink.path
				sink.close
				verbose_out 'driver spawns %s.', path
				child = Process.spawn [path, sink.path], *argv
			ensure
				verbose_out 'driver is waiting for subprocess...'
				Process.waitpid child
				verbose_out 'driver unlinks %s.', path
				File.unlink path
			end
		end
	end

	# A  driver ``runs''  when  no  subcommand was  directly  specified via  the
	# argument vector.  This  is a in-order mode, which  invokes its subcommands
	# one by one, passing one's output to the other's input.
	def run f, n
		verbose_out 'driver entered in-order mode.'
		@subcommands.each_pair do |k, v|
			next unless k
			verbose_out "driver runs #{k}"
			f = v.run f, n
			if @save_temps
				sink = compute_sink v, n
				if sink != STDOUT
					redirect f => sink
					sink.flush
					sink.rewind
					f.close
					f = sink
				end
			end
			return f if @stop_after == k
		end
		return f
	end

	private

	# You know, a compiler's output name is quite complicated.  First, in a very
	# simple case,  a compiler output is  named a.out.  But when  you step aside
	# from  there,  no  linear  rule  should  longer apply.   When  you  have  a
	# SOURCE.EXT  input passed  from the  argument vector,  the  graceful output
	# filename should be SOURCE.EXT2, where  EXT2 represents what kind of output
	# that file  is.  This works as  long as EXT2 is  not the same as  EXT -- in
	# case of  connflict the  source file  can be clobbered  by an  output.  And
	# there can also be a case when no input filename was given; which of course
	# indicates to  read from the  standard input, but  that case needs  also an
	# output name.  Something should be calculated.
	def compute_sink who, target
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
			basename = canonname target
		else
			# case 3; read from STDIN.  Take "STDIN" as a basename.
			basename = "STDIN"
		end
		unless sink
			# extname calculation.
			if who == self
				who = @subcommands[@stop_after] || @subcommands[:linker]
			end
			objext  = ::RbConfig::CONFIG["OBJEXT"]
			exeext  = ::RbConfig::CONFIG["EXEEXT"]
			dlext   = ::RbConfig::CONFIG["DLEXT"]
			extname = case who
						 when @subcommands[:preprocessor] then return STDOUT
						 when @subcommands[:compiler]     then 'c'
						 when @subcommands[:assembler]    then objext
						 else
							 if @subcommands[:linker].shared
								 # shared mode -- SOURCE.so needed
								 dlext
							 else
								 # generate a.out or whatever
								 basename = 'a'
								 exeext.empty? ? 'out' : exeext
							 end
						 end
			sink = sprintf "%s.%s", basename, extname
		end
		verbose_out 'driver opens output file %s', sink
		return open sink, 'w+b'
	end

	# This is a  helper function to spawn a pager  process when possible.  PAGER
	# environment variable is honored, and if not set, pager(1) is searched.  If
	# that is also missing, uses more(1).
	def pager_out str, *rest
		if STDOUT.isatty
			pager = if ENV['PAGER'] then ENV['PAGER']
					  elsif File.exist? '/usr/bin/pager' then '/usr/bin/pager'
					  else 'more' # search $PATH
					  end
			r, w = IO.pipe
			pid = Process.spawn pager, in: r
			w.puts str, *rest
			w.close
			Process.waitpid pid
		else
			STDOUT.puts str, *rest
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
