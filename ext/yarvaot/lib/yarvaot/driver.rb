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
		@pipe    = false
		@verbose = false
		@opt     = OptionParser.new self.class.name_to_display + ' OPTIONS:', 30

		# some default options
		@opt.on_tail '-v', '--verbose', 'Gets annoying.' do |optarg|
			@verbose = optarg
		end
		@opt.on_tail '-h', '--help', 'This is it.' do puts @opt end
	end

	def help_string
		@opt.to_s
	end

	def consume argv
		# argv must be destructively modified not to propagate unknown options to
		# children  subcommands, so  order! should  directly be  applied  to argv
		# itself, not a copy of it.
		i = argv.size
		@opt.order! argv
		return argv.size == i
	rescue OptionParser::InvalidOption => e
		# pass unknown options
		e.recover argv
		return false
	end

	def run argv
		# should be overridden by subclasses
		consume argv
		argv.each do |i|
			open i, 'rb' do |f|
				run_file f, i
			end
		end
	end

	def run_file f, i
		# should be overridden by subclasses
		f
	end

	private
	def verbose_out fmt, *va_list
		STDERR.printf fmt.chomp << "\n", *va_list if @verbose
	end

	def redirect h
		buf = String.new
		h.each_pair do |from, to|
			begin
				while from.readpartial 32768, buf
					j = to.write buf
					raise Errno::EPIPE if j != buf.length
				end
			rescue EOFError
			rescue IOError
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
		@sink         = nil
		@preprocessor = YARVAOT::Preprocessor.new
		@compiler     = YARVAOT::Compiler.new
		@assembler    = YARVAOT::Assembler.new
		@linker       = YARVAOT::Linker.new
		@subcommands  = [@preprocessor, @compiler, @assembler, @linker]

		objext = ::RbConfig::CONFIG["OBJEXT"]
		exeext = ::RbConfig::CONFIG["EXEEXT"]
		exeext = 'out' if exeext.empty?
		@opt.on '-E', '--stop-after-preprocess', <<-'begin'.strip do
                                   Just do preprocess, do not link.  The output
                                   is in the form of preprocessed ruby script.
		begin
			@stop_after = :preprocess
		end

		@opt.on '-c', '--stop-after-compile', <<-'begin'.strip do
                                   Preprocess and compile the input, but do not
                                   assemble.  The  output is  in the form  of C
                                   language.
		begin
			@stop_after = :compile
		end

		@opt.on '-S', '--stop-after-assemble', <<-'begin'.strip do
                                   Compile and  assemble the input,  but do not
                                   link.   The  output  is  in the  form  of  a
                                   machine  native object  file,  e.g.  an  ELF
                                   object.
		begin
			@stop_after = :assemble
		end

		@opt.on '-o', '--output=FILE', <<-"begin".strip do |optarg|
                                   Output to  a file  named FILE, instead  of a
                                   default sink.  Without this option a default
                                   data   sink  for   an  executable   file  is
                                   `a.#{exeext}',  for an  assembled  object is
                                   `SOURCE.#{objext}', for a compiled assembler
                                   code is  `SOURCE.c', and for  a preprocessed
                                   ruby script is the standard output.
		begin
			@sink = optarg
		end

		@opt.on_tail '-v', '--verbose', 'Gets annoying.' do |optarg|
			@verbose = optarg
			@subcommands.each do |i|
				i.consume ['--verbose']
			end
			STDERR.puts RUBY_DESCRIPTION
		end

		@opt.on_tail '-h', '--help', 'This is it.' do
			sub = [
					 self, @preprocessor, @compiler, @assembler, @linker
			].map do |i| i.help_string + "\n" end
			puts <<'HDR1', <<"HDR2", *sub
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
    assemble                       This   is  a  wrapper   to  a   C  compiler.
                                   Generates a  assembler-output machine binary
                                   object from a C source code generated by the
                                   above compiler subcommand.
    link                           Links   every    necessary   libraries   and
                                   assembler  outputs into a  single executable
                                   file, or a single ruby extension library.

HDR2
			Process.exit
		end
	end

	# actually drive subcommands
	def run arg0, argv
		@arg0 = arg0
		remain = @subcommands.dup
		remain.unshift self # order matters
		until remain.empty?
			remain.reject! do |i|
				i.consume argv
			end
		end
		verbose_out 'driver started.'

		case target = argv.shift
		when 'preprocess' then @preprocessor.run argv
		when 'compile'    then @compiler.run argv
		when 'assemble'   then @assembler.run argv
		when 'link'       then @linker.run argv
		else
			verbose_out 'driver entered in-order mode.'
			# opening input file here, preventing outer-process attackers to choke
			# our filesystem.
			fin = case target
					when '-', NilClass
						STDIN
					when String
						File.open target, 'rb'
					else
						raise TypeError, target.inspect
					end
			verbose_out 'driver opened input file %s.', fin.path
			fout = run_file fin, target
			sink = compute_sink target
			redirect fout => sink
		end
	end

	def run_file fin, fn
		verbose_out 'driver runs preprocessor'
		fd1 = @preprocessor.run_file fin, fn
		return fd1 if @stop_after == :preprocess
		verbose_out 'driver runs compiler'
		fd2 = @compiler.run_file fd1, fn
		return fd2 if @stop_after == :compile
		verbose_out 'driver runs assembler'
		fd3 = @assembler.run_file fd2, fn
		return fd3 if @stop_after == :assemble
		verbose_out 'driver runs linker'
		fd4 = @linker.run_file fd3, fn
		return fd4
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
						 when :preprocess then return STDOUT
						 when :compile    then 'c'
						 when :assemble   then ::RbConfig::CONFIG["OBJEXT"]
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
