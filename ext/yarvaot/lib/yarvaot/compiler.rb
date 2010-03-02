#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.
require_relative 'namespace'

# This is the compiler proper, ruby -> C transformation engine.
class YARVAOT::Compiler < YARVAOT::Subcommand

	include YARVAOT::Converter

	# Instructions that touch CFPs
	Invokers = [
		:send, :leave, :finish, :throw, :invokeblock, :invokesuper, :defineclass,
		:opt_plus, :opt_minus, :opt_mult,  :opt_div, :opt_mod, :opt_not, :opt_eq,
		:opt_neq,  :opt_lt,  :opt_le,  :opt_gt,  :opt_ge,  :opt_ltlt,  :opt_aref,
		:opt_aset, :opt_length, :opt_size, :opt_succ, :opt_call_c_function,
	]

	# Instructions that touch PCs
	Branchers = [
		:branchunless,   :branchif,  :jump,   :getinlinecache,  :onceinlinecache,
		:opt_case_dispatch
	]

	# Instantiate.  Does nothing yet.
	def initialize
		super
		@strmax      = 509
		@opts        = Hash.new
		@namespace   = YARVAOT::Namespace.new

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
			@opts[:debug_level] = level || 1
		end

		@opt.on '-O [N]', <<-'begin'.strip, Integer do |level|
                                   Sets  optimization "level".   Default  is 0.
                                   Currently  optimization  levels  of range  0
                                   through  3  are  defined:  0 does  no  opti-
                                   mization, 1 to  enable something, 2 to more,
                                   and 3 to even  more.  All values below 0 are
                                   interpreted as  0, while all  values above 3
                                   are interpreted as  3.  Note that this level
                                   is for optimization  done when a ruby script
                                   is  compiled into C  program.  A  C compiler
                                   may have different compile options.
		begin
			level ||= 0
			if level <= 0
				@opts.clear
			elsif level == 1
				@opts.merge! level1opts
			elsif level == 2
				@opts.merge! level2opts
			else
				@opts.merge! allopts
			end
			@optlv = level
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

		@opt.on '--namemax=N', <<-'begin'.strip, Integer do |n|
                                   Length of  a longest static  identifier name
                                   that  the underlying  C  compiler can  take.
                                   Default is  31, which is the  infinum of the
                                   maximal length  of the local  variable names
                                   that  an  ANSI-conforming  C  compiler  must
                                   understand.
		begin
			@namespace   = YARVAOT::Namespace.new n
		end

		@opt.on '--strmax=N', <<-'begin'.strip, Integer do |n|
                                   Length  of a longest  C string  literal that
                                   the underlying C compiler can take.  Default
                                   is 509, which is  the infinum of the maximal
                                   length  of  the   string  literals  that  an
                                   ANSI-conforming C compiler must understand.
		begin
			@strmax = n
		end
	end

	# Run.  Eat the file, do necessary conversions, then return a new file.
	#
	# One thing  to note is  that this method  invokes a process  inside because
	# the input file  is normally a pipe from  preprocessor stage... which means
	# reading from it tend to block.
	def run f, n
		run_in_pipe f do |g|
			verbose_out 'compiler started.'
			h, t = intercept f
			RubyVM::InstructionSequence.compile_option = @opts
			iseq = RubyVM::InstructionSequence.new h, n
			verbose_out 'compiler generated iseq.'
			@namemax ||= YARVAOT::Namespace.new
			compile t.value, n, iseq, g
			verbose_out 'compiler generated C code.'
		end
	end

	private

	# This is a technique to enclose an object to a lambda's lexical scope.
	def gencb flag
		lambda do |optarg|
			@iseq_compile_option[flag] = optarg
		end
	end

	# Helper function, to split an IO into two
	def intercept f
		r, w = IO.pipe
		t = Thread.start do
			a = String.new
			b = String.new
			begin
				while f.readpartial 32768, b
					w.write b
					a.concat b
				end
			rescue EOFError
			ensure
				f.close rescue nil
				w.close rescue nil
			end
			a
		end
		return r, t
	end

	# Toplevel to trigger compilation
	def compile str, n, iseq, io
		toplevel = recursive_transform iseq
		embed_sourcecode str, n

		Template.trigger binding
	end

	# This is an ERB template to  generate a C sourcecode.
	#
	# Technical note: prior to its  invocation, an extension library entry point
	# is casted as "void (*)(void)".   But a function which rb_protect() expects
	# to have in its first argument is of type "VALUE (*)(VALUE)".  The function
	# type of  a generated entry  point is subject  to change in future  when we
	# abandon rb_protect().
	Template = ERB.new <<-'end', 0, '%', 'io'
/*
 * Auto-generated C sourcecode using YARVAOT, a Ruby to C compiler.
 *
 * This  file includes  some materials  from  the Ruby  distribution. They  are
 * copyrighted by their authors, and  are provided here either under the Ruby's
 * license, or under the GNU Public License version 2.  If you are not familiar
 * with them, please consult:
 *
 *   - http://www.ruby-lang.org/en/about/license.txt
 *   - http://www.gnu.org/licenses/gpl-2.0.txt
 */
#include <ruby/ruby.h>
#include <ruby/encoding.h>
#include <ruby/yarvaot.h>

/* This cannot be a typedef */
#if !defined(__GNUC__) || (__GNUC__ < 4) || \
      ((__GNUC__ == 4) && __GNUC_MINOR__ < 4)
#define sourcecode_t struct yarvaot_lenptr_tag
#else
#define sourcecode_t struct yarvaot_lenptr_tag \
    __attribute__((__unused__))
#endif

/* control frame is opaque */
#define cfp_pc(reg) (reg[0])
#define cfp_sp(reg) (reg[1])
#define th_cfp(th)  (th[4])
#define ic(n) (struct iseq_inline_cache_entry*)(ic + (n) * sizeof_ic)
#define gentry(n) (VALUE)rb_global_entry(n)

static size_t sizeof_ic = 0;
%@namespace.each_static_decls do |decl|
<%= decl %>
%end

%@namespace.each_funcs do |decl|
<%= decl %>
%end

VALUE
Init_<%= canonname n %>(VALUE unused)
{
%@namespace.each_nonstatic_decls do |decl|
    <%= decl %>
%end
    sizeof_ic = yarvaot_sizeof_ic();
%@namespace.each_initializers do |init|
    <%= init %>
%end

    /* finish up */
#define reg(n)                     \
    rb_gc_register_mark_object(n); \
    switch(BUILTIN_TYPE(n)) {      \
    case T_STRING:                 \
    case T_ARRAY:                  \
        hide_obj(n);               \
        break;                     \
    }
#define bye(n)                     \
    n = Qundef

%@namespace.each do |i|
%  if /\bVALUE\b/.match i.declaration
%    if /\Astatic\b/.match i.declaration
    reg(<%= i.name %>);
%    else
    bye(<%= i.name %>);
%    end
%  end
%end
#undef reg

    /* kick */
    return rb_iseq_eval(<%= toplevel %>);
}
	end
	#' <- needed to f*ck emacs

	# This is where  the conversion happens.  ISeq array is  nested, so this can
	# be called recursively.
	def recursive_transform iseq, parent = nil, needfunc = false
		return needfunc ? '0' : 'Qnil' if iseq.nil?
		ary = format_check iseq
		info, name, file, line, type, locals, args, excs, body = ary
		fnam = @namespace.new 'func_' + name, :uniq
		enam = @namespace.new 'iseq_' + name, :uniq
		verbose_out "compiler is now compiling: %s -> %s", name, fnam
		b, e = prepare body, excs, enam
		genfunc fnam, enam, type, name, file, line, b
		genexpr fnam, enam, name, iseq, e, b, parent
		return needfunc ? fnam : enam
	end

	# ISeq#to_ary format validation
	#
	# Only checks format, not for stack consistency.
	def format_check iseq
		x, y, z, w, *ary = *iseq.to_a
		if x != 'YARVInstructionSequence/SimpleDataFormat' or
			y != 1 or z != 2 or w != 1 then
			raise ArgumentError, 'wrong format'
		end
		return *ary
	end

	# This does  a tiny  transformation over  the ISeq body.   When an  ISeq was
	# compiled into  a C  function, that function  would be invoked  from ISeq's
	# opt-call-c-function  instruction.  The problem  is, that  insn is  2 words
	# length.  So  inserting an  OCCF insn into  a ISeq  might not work  on some
	# cases, one of which is illustrated like this:
	#
	#     putobject   obj
	#     send        method 0, nil, 0, <ic>
	#     pop                                 # <- we need OCCF here
	#   label:
	#     putnil
	#
	# So we  have to deal with  those situation by  searching "send" instruction
	# and replace it by a series of send, label, nop, nop.
	#
	#     putobject   obj
	#     send        method 0, nil, 0, <ic>
	#   label:                                # new!
	#     nop                                 # new!
	#     nop                                 # new!
	#     pop
	#   label:
	#     putnil
	#
	# And the OCCF can happily squash those nops.
	def prepare a, b, p
		labels = Hash.new
		phony = [:phony, nil]
		case a[0] when Symbol
			x, emu_pc = [], 0
		else
			x, emu_pc = [phony], 2
		end
		y = b.dup
		a.each_with_index do |i, j|
			x << i
			case i
			when Symbol
				labels.store i, emu_pc
				x << phony
				emu_pc += 2
			when Array
				emu_pc += i.size
				case i.first when *Invokers
					unless a[j+1].is_a? Symbol # that case does not need it
						l = "label_phony_#{emu_pc}".intern
						labels.store l, emu_pc
						x << l
						x << phony
						emu_pc += 2
					end
				end
			end
		end
		x.map! do |i|
			case i
			when Integer
				i
			when Symbol
				"yarv_#{labels[i]}".intern
			when Array
				i.map! do |j|
					if j.is_a? Symbol and /\Alabel_/.match j
						"yarv_#{labels[j]}".intern
					elsif j.is_a? Array # CDHASH
						j.map! do |k|
							if k.is_a? Symbol and /\Alabel_/.match k
								"yarv_#{labels[k]}".intern
							else
								k
							end
						end
					else
						j
					end
				end
				i
			end
		end
		y.map! do |(t, i, s, e, c, sp)|
			j = recursive_transform i, p
			k = Quote.new j
			p.depends j if j.is_a? @namespace
			[t, k,
			 "yarv_#{labels[s]}".intern,
			 "yarv_#{labels[e]}".intern,
			 "yarv_#{labels[c]}".intern,
			 sp]
		end
		return x, y
	end

	# Generates  a   ISeq  internal  function,  which  actually   runs  on  iseq
	# evaluations.
	def genfunc fnam, enam, type, name, file, line, body
		fnam.declaration = 'static rb_insn_func_t'
		fnam.definition = FunctionTemplate.result binding
	end

	# This is almost a Ruby-version iseq_build_body().
	FunctionTemplate = ERB.new <<-'end', 0, '%-'

/* <%= type %>: <%= name %> */
/* from <%= file %> line <%= line %> */
rb_control_frame_t*
<%= fnam %>(rb_thread_t* t, rb_control_frame_t* r)
{
    static VALUE* pc  = 0;
    static char*  ic  = 0; /* char* to suppress pointer-arith warnings */
    rb_control_frame_t* saved_r = r;

    if(UNLIKELY(pc == 0))
        pc = yarvaot_get_pc(r);
    if(UNLIKELY(ic == 0))
        if(yarvaot_set_ic_size(r, <%= count_ic body %>))
            ic = yarvaot_get_ic(r);

%emu_pc = 0
again:
    switch(cfp_pc(r) - pc) {
%body.each do |i|
%	case i
%	when Symbol, Numeric
%		# ignore
%	when Array
<%= genfunc_geninsn emu_pc, i, enam %>;
%	   emu_pc += i.size
%	end
%end

        /* FALLTHRU */
    default:
        rb_vmdebug_debug_print_register(t);
        rb_bug("inconsistent pc %d", cfp_pc(r) - pc);
    }
    /* NOTREACHED */
}
	end

	# count how many ICs ar used
	def count_ic b
		max = -1
		b.each do |i|
			case i when Array
				op, *argv = *i
				case op when :phony then else
					ta = YARVAOT::INSNS[op][:opes].zip argv
					ta.each do |(t, v), a|
						case t when 'IC'
							max < a and max = a
						end
					end
				end
			end
		end
		return max + 1
	end

	# For a instruction _insn_, there is  an equivalent C expression to run that
	# insn.
	def genfunc_geninsn pc, insn, parent
		ret = "    case #{pc}: "
		op, *argv = *insn
		case op when :phony
			# phony insns are placeholders to opt_call_c_function.
			ret << 'r = yarvaot_insn_nop(t, yarvaot_insn_nop(t, r));'
		else
			s = genfunc_genargv op, argv, parent, pc
			body = if s.empty?
						 "r = yarvaot_insn_#{op}(t, r)"
					 else
						 "r = yarvaot_insn_#{op}(t, r, #{s})"
					 end
			case op
			when *Branchers
				body += ";\n"\
					 "        goto again"
			when *Invokers
				body += ";\n" \
					 "        if(UNLIKELY(r != saved_r))\n" \
					 "            return r;\n" \
					 "        else\n" \
					 "            goto again"
			end
			ret << body
		end
	end

	# ISeq operands transformation.
	def genfunc_genargv op, argv, parent, pc
		type = YARVAOT::INSNS[op][:opes].map do |i| i.first end
		ta = type.zip argv
		ta.map! do |(t, a)|
			case t
			when 'ISEQ'
				if a.nil? # null pointer
					0
				else
					i = recursive_transform a, parent
					"DATA_PTR(#{i})"
				end
			when 'lindex_t', 'dindex_t', 'rb_num_t'
				a
			when 'IC'
				"ic(#{a})"
			when 'OFFSET'
				m = /\d+/.match a.to_s
				if m
					"(OFFSET)#{m.to_s.to_i - pc - argv.size - 1}" # 1 for op
				else
					raise a.inspect
				end
			when 'CDHASH'
				# CDHASH  is actually  a mapping  of VALUE  => Fixnum,  where those
				# fixnums are fixnum-converted OFFSET value.
				tmp = Hash.new
				a.each_slice 2 do |k, v|
					m = /\d+/.match v.to_s
					if m
						n = m.to_s.to_i - pc - argv.size - 1
					else
						raise a.inspect
					end
					tmp.store k, n
				end
				name = robject2csource tmp
				name.depends parent
			when 'VALUE'
				name = robject2csource a
				case name when @namespace
					parent.depends name
				end
				name
			when 'GENTRY' # struct rb_global_entry*
				sym = robject2csource a
				parent.depends sym
				"gentry(#{sym.name})"
			when 'ID' # not the object, but its interned integer
				sym = robject2csource a
				parent.depends sym
				sym.name
			else
				raise TypeError, [op, ta].inspect
			end
		end
		ta.join ', '
	end

	# Several ways are there  to convert an ISeq array into C  source but I find
	# it the most convenient when passing that to rb_iseq_load().
	def genexpr fnam, enam, inam, iseq, excs, body, parent
		b = Array.new
		body.each do |i|
			case i when Array
				case i.first when :phony
					j = Quote.new "ULONG2NUM((unsigned long)#{fnam})"
					b << [:opt_call_c_function, j]
				else
					i.size.times do
						b << [:nop]
					end
				end
			else
				b << i
			end
		end
		# Beware! ISeq#to_a return values are shared among invokations!
		tmp = iseq.to_a.dup
		tmp[-2] = excs
		tmp[-1] = b
		anam = @namespace.new 'ary_' + inam, :uniq
		robject2csource tmp, :volatile, anam
		enam.declaration    = 'static VALUE'
		enam.definition     = "static VALUE #{enam} = Qundef;"
		enam.initialization = sprintf '%s = rb_iseq_load(%s, %s, 0);',
												enam, anam, parent || 'Qnil'
		enam.depends anam
	end

	# Embed  the  original  source  code.   This  is  expected  to  be  used  in
	# combination with  __END__ handling, which is not  implemented yet, because
	# we plan to use multi-VM APIs for that purpose.
	def embed_sourcecode str, fn
		gen_each_lenptr 'filename', fn
		gen_each_lenptr 'filecoding', str.encoding.name
		gen_each_lenptr 'src', str
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
