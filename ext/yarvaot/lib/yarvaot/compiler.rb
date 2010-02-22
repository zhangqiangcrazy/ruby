#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.
require 'uuid'
require 'erb'

# This is the compiler proper, ruby -> C transformation engine.
class YARVAOT::Compiler < YARVAOT::Subcommand

	# This is used to limit the UUID namespace
	Namespace = UUID.parse 'urn:uuid:71614e1a-0cb4-11df-bc41-5769366ff630'

	# Instantiate.  Does nothing yet.
	def initialize
		super
		@optlv               = 0
		@namemax             = 31
		@strmax              = 509
		@toplevel            = String.new
		@preambles           = String.new
		@Trailers            = String.new
		@namespace           = Hash.new
		@namedb              = Hash.new do |h, k| h.store k, Array.new end
		@sourcecodes         = Array.new
		@functions           = Array.new
		@generators          = Hash.new
		@static              = Hash.new
		@iseq_compile_option = Hash.new
		@emit_disasm         = false

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
                                   interpreted as  0, while all  values above 3
                                   are interpreted as  3.  Note that this level
                                   is for optimization  done when a ruby script
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
			@namemax = n
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

		@opt.on '--[no-]emit-disasm', <<-'begin'.strip, TrueClass do |n|
                                   Emits VM-included disassembler output to the
                                   generating C  source file as  comments. This
                                   is mainly for debugging.
		begin
			@emit_disasm = n
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
			str = f.read # wait preprocessor
			RubyVM::InstructionSequence.compile_option = @iseq_compile_option
			iseq = RubyVM::InstructionSequence.new str, n
			verbose_out 'compiler generated iseq.'
			compile str, n, iseq
			verbose_out 'compiler generated C code.'
			stringize n do |s|
				g.write s
			end
			verbose_out 'compiler finished.'
		end
	end

	private

	# This is a technique to enclose an object to a lambda's lexical scope.
	def gencb flag
		lambda do |optarg|
			@iseq_compile_option[flag] = optarg
		end
	end

	# Toplevel to trigger compilation
	def compile str, n, iseq
		@preambles = PreamblesTemplate.result binding
		embed_sourcecode str, n
		embed_debug_disasm iseq if @emit_disasm
		@toplevel, * = recursive_transform iseq

		ndb = @namedb.values.flatten 1
		ndb.map! do |(t, e)|
			[t, 'y_' + e]
		end
		@namedb = ndb
		values = @namedb.select do |(t, e)| t == 'VALUE' end.transpose.last
		values ||= Array.new

		@trailers = TrailersTemplate.result binding
	end

	# Feeds compiled C source code little by little to the given block.
	def stringize name # :yields: string
		yield @preambles
		@namedb.each do |(t, n)|
			if decl = @static[n]
				yield "static #{t} #{n}#{decl};\n"
			else
				# default decls
				case t
				when 'VALUE'
					yield "static #{t} #{n} = Qundef;\n"
				when 'ID', 'ISEQ', /\*\z/
					yield "static #{t} #{n} = 0;\n"
				else
					yield "static #{t} #{n};\n"
				end
			end
		end
		yield "\n"
		@sourcecodes.flatten.each do |i|
			yield i
		end
		@functions.each do |f|
			yield "\n"
			yield f
		end
		yield @trailers
	end

	# This  is an  ERB template  to  generate a  C file  preamble.  It  normally
	# generates a series of #include's  needed, a series of #define's needed and
	# (if  any) a  series of  external  function declarations  missing from  the
	# included header files.
	PreamblesTemplate = ERB.new <<-'end', 0, '%'
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

#define yarvaot_insn_jump_intr(t, n, l)         \
    RUBY_VM_CHECK_INTS_TH(t);                   \
    cfp_pc(r) = pc + n;                         \
    goto l;
#define yarvaot_insn_jump_nointr(t, n, l)       \
    cfp_pc(r) = pc + n;                         \
    goto l;
#define yarvaot_insn_branchif_intr(t, n, l)     \
    if(RTEST(*--cfp_sp(r))) {                   \
        RUBY_VM_CHECK_INTS_TH(t);               \
        cfp_pc(r) = pc + n;                     \
        goto l;                                 \
    }                                           \
    else {                                      \
        /* need to consume pc */                \
        cfp_pc(r) += 2;                         \
    }                   
#define yarvaot_insn_branchif_nointr(t, n, l)   \
    if(RTEST(*--cfp_sp(r))) {                   \
        cfp_pc(r) = pc + n;                     \
        goto l;                                 \
    }                                           \
    else {                                      \
        /* need to consume pc */                \
        cfp_pc(r) += 2;                         \
    }
#define yarvaot_insn_branchunless_intr(t, n, l) \
    if(!RTEST(*--cfp_sp(r))) {                  \
        RUBY_VM_CHECK_INTS_TH(t);               \
        cfp_pc(r) = pc + n;                     \
        goto l;                                 \
    }                                           \
    else {                                      \
        /* need to consume pc */                \
        cfp_pc(r) += 2;                         \
    }
#define yarvaot_insn_branchunless_nointr(t, n, l)\
    if(!RTEST(*--cfp_sp(r))) {                   \
        cfp_pc(r) = pc + n;                      \
        goto l;                                  \
    }                                            \
    else {                                       \
        /* need to consume pc */                 \
        cfp_pc(r) += 2;                          \
    }

static const size_t sizeof_ic = 0; /* initialized later */
	end
	#' <- needed to f*ck emacs

	# This is an ERB template to  generate a C sourcecode trailer, which is, the
	# DLL entry point function.
	#
	# Technical note: prior to its  invocation, an extension library entry point
	# is casted as "void (*)(void)".   But a function which rb_protect() expects
	# to have in its first argument is of type "VALUE (*)(VALUE)".  The function
	# type of  a generated entry  point is subject  to change in future  when we
	# abandon rb_protect().
	TrailersTemplate = ERB.new <<-'end', 0, '%'

VALUE
Init_<%= canonname n %>(VALUE unused)
{
    /* initializations */
%# generator entries have mutual dependencies so order matters
%@generators.each_pair do |k, v|
    <%= k %> = <%= v %>;
%end

    /* register global variables */
#define reg(n) \
    rb_gc_register_mark_object(n);\
    hide_obj(n)
%values.each do |i|
    reg(<%= i %>);
%end
#undef reg

    /* kick */
    return rb_iseq_eval(<%= @toplevel %>);
}
	end

	# Note, that a sourcecode starts from line one.
	def embed_sourcecode str, n
		verbose_out 'compiler embedding %s into c source...', n
		enc = namegen 'src', 'char const*'
		register_declaration_for enc, %' = "#{str.encoding.name}"'
		a = rstring2cstr str, $/
		a.each do |(expr, len)|
			nam = namegen 'src', 'sourcecode_t', :realuniq
			str = sprintf " = { %#05x, %s }", len, expr
			register_declaration_for nam, str
		end
	end

	# For debug, apply within.
	def embed_debug_disasm iseq
		verbose_out 'compiler embedding iseq disasm..'
		@sourcecodes << "/*\n"
		str = iseq.disasm
		str.gsub! '/*', '/\\*'
		str.gsub! '*/', '*\\/'
		@sourcecodes << str << "\n*/\n"
	end

	# This is where  the conversion happens.  ISeq array is  nested, so this can
	# be called recursively.
	#
	# Returns a set of names to refer to 
	# * the converted ISeq,
	# * the converted function body, 
	# * and the converted quasi-iseq.
	def recursive_transform iseq
		return '0', '0', '0' if iseq.nil?
		ary = format_check iseq
		info, name, file, line, type, locals, args, excs, body = ary
		verbose_out "compiler is now compiling: %s", name
		b2   = prepare body
		inam = namegen 'i' + ary[1], 'VALUE', :uniq
		fnam = genfunc iseq, name, b2, file, line, type
		qnam = geniseq fnam, inam, ary, b2		
		return inam, fnam, qnam
	end

	# This does  a tiny  transofrmation over  the ISeq body.   When an  ISeq was
	# compiled  into  a  C  function,  that function  was  invoked  from  ISeq's
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
	def prepare a
		phony = [:phony, nil]
		idx = 0
		ret = [phony]
		a.each do |i|
			case i
			when Integer, Symbol then ret << i
			when Array   then
				ret << i
				if i.first == :send
					ret << "label_phony_#{idx}".intern
					ret << phony
					idx += 1
				end
			else raise i.inspect
			end
		end
		ret
	end

	class Quote # :nodoc:
		def initialize val
			@unquote = val
		end
		attr_reader :unquote
	end

	def geniseq fnam, inam, ary, body
		decl = " = {\n"
		decl << "    ISEQ_TYPE_#{ary[4].upcase},\n"
		decl << "    #{rstring2quasi ary[1]},\n"
		decl << "    #{rstring2quasi ary[2]},\n"
		decl << "    #{ary[3]},\n"
		decl << "    #{geniseq_genary ary[5]},\n"
		case i = ary[6]
		when Array
			a = i.dup
			a[1] = geniseq_genary a[1]
			decl << "    {#{a.join ', '}},\n"
		else
			decl << "    { #{i}, 0, 0, 0, 0, 0, 1, },\n"
		end
		decl << "    #{geniseq_gentable ary[7]},\n"
		decl << "    #{geniseq_gentemplate body},\n"
		decl << "    #{fnam}, }"
		qnam = namegen fnam, 'struct yarvaot_quasi_iseq_tag', :uniq
		register_declaration_for qnam, decl
		register_generator_for inam, "yarvaot_geniseq(&#{qnam})"
		return qnam
	end

	def inject_internal ary, desired, type, term  #:nodoc:
		decl = ary.inject "[] = {\n" do |r, str|
			yield r, str
		end
		decl << "    #{term},\n}"
		name = namegen desired, type
		register_declaration_for name, decl
		name
	end

	# generates arrays of quasi strings
	def geniseq_genary ary
		return 0 if ary.nil?
		return 0 if ary.empty?
		inject_internal ary, nil,
							 'struct yarvaot_quasi_string_tag',
							 '{ 0, 0, }' do
			|r, i| 
			r << "    #{rstring2quasi i.to_s},\n"
		end
	end

	def geniseq_gentable ary
		return 0 if ary.nil?
		return 0 if ary.empty?
		inject_internal ary, nil,
							 'struct yarvaot_quasi_catch_table_entry_tag',
							 '{CATCH_TYPE_NEXT, 0, 0, 0, 0, 0, }' do
			|r, (t, i, s, e, c, sp)|
			*, q = recursive_transform i
			r << "    { CATCH_TYPE_#{t.to_s.upcase},\n"
			r << "      #{q == '0' ? q : '&'+q},\n"
			r << %'      "#{s}",\n'
			r << %'      "#{e}",\n'
			r << %'      "#{c}",\n'
			r << "      #{sp}, },\n"
		end
	end
	
	def geniseq_gentemplate ary
		inject_internal ary, nil, 'char const*', '"end"' do |r, i|
			case i
			when Integer, Symbol then r << %'\n    "#{i}", '
			when Array   then
				if i.first == :phony
					r << '"", '
				else
					i.each do |j|
						r << '0, '
					end
				end
				r
			else raise i.inspect
			end
		end
	end

	def genfunc iseq, name, body, file, line, type # :nodoc:
		fnam = namegen name, 'rb_insn_func_t', :uniq
		labels_seen = Hash.new
		ic_idx = [0]
		func = FunctionTemplate.result binding
		@functions.push func
		fnam
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
    static size_t sic = 0;

    if(UNLIKELY(pc == 0))
        pc = yarvaot_get_pc(r);
    if(UNLIKELY(ic == 0))
        ic = yarvaot_get_ic(r);

%emu_pc = 0
    /* Beware!  labels are  *not* equal to  the pc, because  some optimizations
     * and transoformations are made. */
    switch(cfp_pc(r) - pc) {
%body.each do |i|
%	case i
%	when Symbol
%		labels_seen.store i, true
    <%= i %>:
%	when Numeric
%		# ignore
%	when Array
<%= genfunc_geninsn emu_pc, i, iseq, labels_seen, ic_idx, %>;
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

	def genfunc_geninsn pc, insn, parent, labels_seen, ic_idx #:nodoc:
		jumpers = [
			:send, :leave,
			:invokeblock, :invokesuper,
			:getinlinecache, :onceinlinecache, 
			:opt_case_dispatch
		]
		ret = "    case  #{pc}: "
		op, *argv = *insn
		ret << case op
				 when :nop, :phony
					 # nop is NOT actually a no-op... it should update the pc.
					 "cfp_pc(r) += #{insn.size}"
				 when :branchunless, :branchif, :jump
					 l = argv[0]
					 m = /\d+/.match l.to_s
					 s = if labels_seen.has_key? l
							  'intr'
						  else
							  'nointr'
						  end
					 "yarvaot_insn_#{op}_#{s}(t, #{m[0]}, #{l})"
				 else
					 s = genfunc_genargv op, argv, parent, ic_idx
					 body = if s.empty?
								  "r = yarvaot_insn_#{op}(t)"
							  else
								  "r = yarvaot_insn_#{op}(t, #{s})"
							  end
					 if jumpers.include? op
						 body + ";\n" + <<-end.chomp
        if(UNLIKELY(cfp_pc(r) - pc != #{pc + insn.size}))
            return r
						 end
					 else
						 body
					 end
				 end
	end

	def genfunc_genargv op, argv, parent, ic_idx # :nodoc:
		type = YARVAOT::INSNS[op][:opes].map do |i| i.first end
		ta = type.zip argv
		ta.map! do |(t, a)|
			case t
			when 'ISEQ'
				if a.nil? # null pointer
					0
				else
					i, * = recursive_transform a
					"DATA_PTR(#{i})"
				end
			when 'lindex_t', 'dindex_t', 'rb_num_t'
				a
			when 'IC'
				ic_idx[0] += 1
				"ic(#{ic_idx[0]})"
			when 'OFFSET' # ??
				m = /\d+/.match a.to_s
				if m
					"(OFFSET)#{m}"
				else
					raise a.inspect
				end
			when 'CDHASH', 'VALUE'
				robject2csource a
			when 'GENTRY' # struct rb_global_entry*
				sym = robject2csource a
				"gentry#{sym.sub 'ID2SYM', ''}"
			when 'ID' # not the object, but its interned integer
				sym = robject2csource a
				sym.sub 'ID2SYM', ''
			else
				raise TypeError, [op, ta].inspect
			end
		end
		ta.join ', '
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

	# Some kinds of literals are there:
	#
	# - Fixnums,  as well  as true,  false, and  nil: they  are  100% statically
	#   computable while the compilation.  No cache needed.
	# - Bignums, Floats, Ranges and Symbols:  they are almost static, except for
	#   the first time.  Suited for a caching.
	# - Classes: not computable  by the compiler, but once  a ruby process boots
	#   up, they already are.
	# - Strings:  every time  a literal  is evaluated,  a new  string  object is
	#   created.  So a cache won't work.
	# - Regexps: almost  the same  as Strings, except  for /.../o, which  can be
	#   cached.
	# - Arrays and Hashes: they also  generate new objects every time, but their
	#   contents can happen to be cached.
	#
	# Cached objects can  be ``shared'' -- for instance  multiple occasions of an
	# identical bignum can and should point to a single address of memory.
	def robject2csource obj, qnam = nil
		put  = nil # a C expression
		get  = nil # a C expression
		type = 'VALUE'
		case obj
		when Quote # hack
			get  = obj.unquote.to_s
		when Fixnum
			get  = 'LONG2FIX(%d)' % obj
		when TrueClass, FalseClass, NilClass
			get  = 'Q%p' % obj
		when Bignum
			put  = 'rb_cstr2inum("%s", 10)', obj.to_s
			qnam = namegen obj.to_s, type
		when Float
			put  = 'rb_float_new(%g)' % obj
		when Range
			from = robject2csource obj.begin
			to   = robject2csource obj.end
			xclp = obj.exclude_end? ? 0 : 1
			put  = sprintf 'rb_range_new(%s, %s, %d)', from, to, xclp
		when Class
			if obj == Object
				get = 'rb_cObject'
			elsif obj == Array
				get = 'rb_cArray'
			elsif obj == StandardError
				get = 'rb_eStandardError'
			else
				raise TypeError, "unknown literal object #{obj}"
			end
		when Symbol
			# Why a  symbol is not cached  as a VALUE?   Well a VALUE in  C static
			# variable needs to be scanned during GC because VALUEs can have links
			# against some other objects in  general.  But that's not the case for
			# Symbols -- they do not  have links internally.  An ID variable needs
			# no GC because  it's clear they are  not related to GC at  all.  So a
			# Symbol is more efficient when stored as an ID, rather than a VALUE.
			str  = rstring2cstr obj.to_s
			type = 'ID'
			qnam = namegen obj.to_s, type
			get  = 'ID2SYM(%s)' % qnam
			put  = 'rb_intern(%s)' % str.first.first.strip
		when String
			if obj.empty?
				# empty strings do not even need encodings
				get = 'rb_str_new(0, 0)'
			else
				if obj.ascii_only?
					qnam = namegen obj, type
					encn = "US_ASCII"
				else
					encn = obj.encoding.name
				end
				argv = rstring2cstr obj
				tmp  = argv.flatten.join ', '
				put  = sprintf 'vrb_enc_str_new("%s", %s, 0)', encn, tmp
			end
		when Regexp
			opts = obj.options
			srcs = robject2csource obj.source
			put = sprintf 'rb_reg_new_str(%s, %d)', srcs, opts
		when Array
			case n = obj.length
			when 0
				# zero-length  arrays need  no cache,  because a  creation  of such
				# object is fast enough.
				get  = 'rb_ary_new2(0)'
			when 1
				# no speedup, but a bit readable output
				i    = obj.first
				e    = robject2csource i
				s    = 'a' + i.to_s
				qnam = namegen s, type
				put  = 'rb_ary_new3(1, %s)' % e
			else
				put  = 'rb_ary_new3(%d' % obj.length
				obj.each do |x|
					y = robject2csource x
					put << ",\n\t" << y.to_s
				end
				put << ')'
				s = put.sub %r/\Arb_ary_new3\(\d+,\s+/, 'a'
				qnam = namegen s, type
			end
		when Hash
			# Hashes are not computable in a single expression...
			qnam = namegen nil, type
			put  = "rb_hash_new();"
			obj.each_pair do |k, v|
				knam = robject2csource k
				vnam = robject2csource v
				str = sprintf "\n    rb_hash_aset(%s, %s, %s);", qnam, knam, vnam
				put << str
			end
		else
			raise TypeError, "unknown literal object #{obj.inspect}"
		end

		unless put.nil?
			qnam ||= namegen put, type
			register_generator_for qnam, put
		end
		get ||= qnam
		return get
	end

	# From ruby string to quasi string.
	#
	# In contrast to rstring2cstr, this method registers names to the namespace
	# pool, because it needs at least one variable.
	def rstring2quasi str
		ary = rstring2cstr str, "\n"
		name = inject_internal ary, str,
									  'struct yarvaot_lenptr_tag', '{ 0, 0, }' do
			|r, (e, l)|
			s = sprintf "    { %#05x, %s },\n", l, e
			r << s
		end
		%'{ "#{str.encoding.name}", #{name} }'
	end

	def register_declaration_for name, decl
		if old = @static[name]
			if decl != old
				raise RuntimeError,
					"multiple, though not identical, static decls for #{name}:\n" \
					"\t#{old}\n\t#{decl}"
			end
			old.replace decl
		else
			@static[name] = decl
		end
	end

	def register_generator_for name, generator
		if old = @generators[name]
			if generator != old
				raise RuntimeError,
					"multiple, though not identical, generators for #{name}:\n" \
					"\t#{old}\n\t#{generator}"
			end
			old.replace generator
		else
			@generators[name] = generator
		end
	end

	# Generates  a name  unique in  this compilation  unit, with  declaring type
	# _type_.  Takes as much as possible from what's _desired_.
	#
	# Note however, that  an identical argument _desired_ generates  a same name
	# on multiple invocations unless _realuniq_ is true.
	def namegen desired, type, realuniq = false
		str = namegen_internal desired, type, realuniq
		ret = 'y_' + str
		raise "!! #{ret.length} > #@namemax !! : #{ret}" if ret.length > @namemax
		ret
	end

	def namegen_internal desired, type, realuniq
		limit = @namemax - 2 # 2 is 'y_'.length
		unless desired.nil?
			ary = @namedb.fetch desired, Array.new
			if not ary.empty? and not realuniq
				ary.each do |rt, rn|
					return rn if type == rt
				end
			end
			n = nil
			cand0 = as_tr_cpp desired, ''
			cand1 = cand0
			while @namespace.has_key? cand1
				if n.nil?
					n = 1
				else
					n += 1
				end
				cand1 = cand0 + n.to_s
			end
			if cand1.length <= limit
				# OK, take this
				@namedb[desired] << [type, cand1]
				@namespace[cand1] = desired
				return cand1
			end
		end
		if desired
			u = Namespace.new_sha1 desired
		else
			u = UUID.new_random
		end
		if limit >= u.to_s.length
			v = u.to_s
		else
			# An  UUID is  128 bits  length, while  the infinum  of  maximal local
			# variable name length in the  ANSI C is 31 characters.  The canonical
			# RFC4122- style UUID stringization do not work here.
			bpc = 128.0 / limit
			radix = 2 ** bpc
			v = u.to_i.to_s radix.ceil
		end
		namegen_internal v, type, realuniq # try again
	end

	# Returns a 2-dimensional array [[str, len], [str, len], ... ]
	#
	# This is needed because Ruby's String#dump is different from C's.
	def rstring2cstr str, rs = nil
		a = str.each_line rs
		a = a.to_a
		a.map! do |b|
			c = b.each_byte.each_slice @strmax
			c.to_a
		end
		a.flatten! 1
		a.map! do |bytes|
			b = bytes.each_slice 80
			c = b.map do |d|
				d.map do |e|
					case e # this case statement is optimized
					when 0x00 then '\\0'
					when 0x07 then '\\a'
					when 0x08 then '\\b'
					when 0x09 then '\\t'
					when 0x0A then '\\n'
					when 0x0B then '\\v'
					when 0x0C then '\\f'
					when 0x0D then '\\r'
					when 0x22 then '\\"'
					when 0x27 then '\\\''
					when 0x5C then '\\\\' # not \\
					else
						case e
						when 0x20 ... 0x7F then '%c' % e
						else '\\x%x' % e
						end
					end
				end
			end
			c.map! do |d|
				"\n        " '"' + d.join + '"'
			end
			if c.size == 1
				c.first.strip!
			end
			[ c.join, bytes.size, ]
		end
		a
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
