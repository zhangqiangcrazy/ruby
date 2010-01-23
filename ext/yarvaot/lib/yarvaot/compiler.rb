#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.

# This is the compiler proper, ruby -> C transformation engine.
class YARVAOT::Compiler < YARVAOT::Subcommand

	# Instantiate.  Does nothing yet.
	def initialize
		super
		@iseq_compile_option = Hash.new
		allopts = {
			inline_const_cache:       true,
			peephole_optimization:    true,
			tailcall_optimization:    true,
			specialized_instruction:  true,
			operands_unification:     true,
			instructions_unification: true,
			stack_caching:            true,
			trace_instruction:        true,
		}
		level2opts = {
			inline_const_cache:       true,
			peephole_optimization:    true,
			tailcall_optimization:    true,
			specialized_instruction:  true,
		}
		level1opts = {
			inline_const_cache:       true,
			peephole_optimization:    true,
			specialized_instruction:  true,
		}
		@opt.on '-g [N]', <<-'begin'.strip, Integer do |level|
                                   Debug  level, default is  1.  This  sets the
                                   debug level of ruby.  It seems values from 0
                                   to 5  are supported, but  their meanings are
                                   not clear to me.
		begin
			@iseq_compile_option[:debug_level] = level || 1
		end
		@opt.on '-O [N]', <<-'begin'.strip, Integer do |level|
                                   Sets  optimization "level".   Default  is 0.
                                   Currently  optimization  levels  of range  0
                                   through  3  are  defined:  0 does  no  opti-
                                   mization, 1 to  enable something, 2 to more,
                                   and 3 to even  more.  All values below 0 are
                                   intepreted  as 0, while  all values  above 3
                                   are interpreted as  3.  Note that this level
                                   is for  opimization done when  a ruby script
                                   is  compiled into C  program.  A  C compiler
                                   may have different compile options.
		begin
			level ||= 0
			if level <= 0
				@iseq_compile_option.clear
			elsif level == 1
				@iseq_compile_option.merge! level1opts
			elsif level == 2
				@iseq_compile_option.merge! level2opts
			else
				@iseq_compile_option.merge! allopts
			end
		end

		allopts.keys.each do |flag|
			proc = gencb flag
			name = flag.to_s.gsub '_', '-'
			@opt.on "--[no-]#{name}", <<-"end".strip, &proc
                                   Enable (or disable)  VM compile option named
                                   #{flag}.  Note that the author
                                   of this help  string do not fully understand
                                   what it is.  No warranty please.
			end
		end
	end

	def run_file f, n
		g, h = IO.pipe
		Thread.start do
			verbose_out 'compiler started.'
			RubyVM::InstructionSequence.compile_option = @iseq_compile_option
			iseq = RubyVM::InstructionSequence.new f, n
			verbose_out 'compiler generated iseq.'
			h.puts iseq.inspect
			verbose_out 'compiler finished.'
			h.close
		end
		return g
	end

	private
	def gencb flag
		lambda do |optarg|
			@iseq_compile_option[flag] = optarg
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
