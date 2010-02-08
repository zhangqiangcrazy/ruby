#! /some/path/to/ruby
# coding=utf-8

# Ruby to C  (and then, to machine executable)  compiler, originally written by
# Urabe  Shyouhei <shyouhei@ruby-lang.org>  during 2010.   See the  COPYING for
# legal info.
require 'uuid'

# This is the compiler proper, ruby -> C transformation engine.
class YARVAOT::Compiler < YARVAOT::Subcommand

	# This is used to limit the UUID namespace
	Namespace = UUID.parse 'urn:uuid:71614e1a-0cb4-11df-bc41-5769366ff630'

	# Instantiate.  Does nothing yet.
	def initialize
		super
		@toplevel            = ''
		@preambles           = ''
		@namespace           = Hash.new
		@namedb              = Hash.new do |h, k| h.store k, Array.new end
		@sourcecodes         = Array.new
		@functions           = Array.new
		@generators          = Hash.new
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

	def run f, n
		run_in_pipe f do |g|
			verbose_out 'compiler started.'
			str = f.read # wait preprocessor
			RubyVM::InstructionSequence.compile_option = @iseq_compile_option
			iseq = RubyVM::InstructionSequence.new str, n
			verbose_out 'compiler generated iseq.'
			compile str, n, iseq
			verbose_out 'compiler generated C code.'
			stringize n do |str|
				g.write str
			end
			verbose_out 'compiler finished.'
		end
	end

	private

	# toplevel to trigger compilation
	def compile str, n, iseq
		genpreambles
		embed_sourcecode str, n
		embed_debug_disasm iseq
		@toplevel = recursive_transform iseq
	end

	# feeds compiled C source code little by little to the given block.
	def stringize name # :yields: string
		yield @preambles
		n2t = @namedb.values.flatten 1
		n2t = n2t.group_by do |(t, n)|
			t
		end.sort.map do |(t, a)|
			a.sort_by do |(t, n)|
				n
			end
		end.flatten 1
		n2t.map! do |(t, n)|
			[t, 'y_' + n]
		end
		n2t.each do |(t, n)|
			case t
			when 'VALUE'
				yield "static #{t} #{n} = Qundef;\n"
			when 'ID', 'ISEQ', /\*\z/
				yield "static #{t} #{n} = 0;\n"
			else
				yield "static #{t} #{n};\n"
			end
		end
		yield "\n"
		yield @sourcecodes.flatten.join
		@functions.each do |f|
			yield "\n"
			yield f
		end
		yield "\n"
		yield @trailers
		c = canonname name
		yield <<-end

VALUE
Init_#{c}(VALUE ign)
{
    /* register global variables */
		end
		n2t.each do |(t, n)|
			yield "    rb_gc_register_mark_object(#{n});\n" if t == 'VALUE'
		end
		yield "\n    /* initializations */\n"
		# generator entries have mutual dependencies so order matters
		@generators.each_pair do |k, v|
			yield "    #{k} = #{v};\n"
		end
		yield "\n    /* hide them from the ObjectSpace, see [ruby-dev:37959] */\n"
		n2t.each do |(t, n)|
			yield "    hide_obj(#{n});\n" if t == 'VALUE'
		end
		yield <<-end

    /* kick */
    return rb_iseq_eval(#@toplevel);
}
		end
	end

	def genpreambles
		@preambles <<<<-'end'
#include <ruby/ruby.h>
#include <ruby/encoding.h>
#include <ruby/yarvaot.h>

/* This cannot be a typedef */
#if !defined(__GNUC__) || (__GNUC__ < 4) || \
      ((__GNUC__ == 4) && __GNUC_MINOR__ < 4)
#define sourcecode_t static char const
#else
#define sourcecode_t __attribute__((__unused__)) static char const
#endif

/* control frame is opaque */
#define cfp_pc(reg) (reg[0])
#define cfp_sp(reg) (reg[1])
		end
	end

	# Note, that a sourcecode starts from line one.
	def embed_sourcecode str, n
		verbose_out 'compiler embedding %s into c source...', n
		e = rstring2cstr str.encoding.name
		tmp = sprintf "sourcecode_t src_enc[] = %s;\n", e.first.first
		@sourcecodes << tmp
		tmp = str.each_line.map do |i|
			j = rstring2cstr i
			j.map do |k| k.first end
		end
		if tmp.any? do |i| i.size > 1 end then
			tmp.each_with_index do |a, i|
				a.each_with_index do |b, j|
					c = sprintf "sourcecode_t src_%4x_%x[] = %s;\n", i + 1, j, b
					@sourcecodes << c
				end
			end
		else
			tmp.each_with_index do |a, i|
				b = sprintf "sourcecode_t src_%04x[] = %s;\n", i + 1, a.first
				@sourcecodes << b
			end
		end
	end

	def embed_debug_disasm iseq
		verbose_out 'compiler embedding iseq disasm..'
		@sourcecodes << "/*\n"
		str = iseq.disasm
		str.gsub! '/*', '/\\*'
		str.gsub! '*/', '*\\/'
		@sourcecodes << str << "\n*/\n"
	end

	def recursive_transform iseq, maybe_parent = 'Qnil'
		info, name, file, line, type, locals, args, excs, body = format_check iseq
		fnam = namegen name, 'rb_insn_func_t', :uniq
		inam = namegen 'i' + name, 'VALUE', :uniq
		verbose_out "compiler Ruby -> C: %s -> %s()", name, fnam
		geniseq iseq, inam, fnam, maybe_parent
		genfunc fnam, inam, name, body, file, line, type
		inam # used in putiseq
	end

	# This is a technique to enclose an object to a lambda's lexical scope.
	def gencb flag
		lambda do |optarg|
			@iseq_compile_option[flag] = optarg
		end
	end

	class Quote # :nodoc:
		def initialize val
			@val = val
		end
		attr_reader :val
	end

	# Several ways are  there when you create  an ISeq, but I found  it the most
	# convenient to once generate an array, and then kick rb_iseq_load.
	def geniseq iseq, inam, fnam, maybe_parent
		# Watch out! ISeq#to_a is shared among invocations...
		ary = iseq.to_a.dup
		qfunc = Quote.new "ULONG2NUM((unsigned long)(#{fnam}))"
		body = ary.last.dup
		body.map! do |i|
			# should retain size
			case i
			when Symbol, Numeric
				i
			when Array
				[[:nop]] * i.size
			else
				raise TypeError, "unknown %p", i
			end
		end
		body.flatten! 1
		body[0] = [:opt_call_c_function, qfunc]
		body[-1] = [:leave]
		ary[-1] = body
		rnam = robject2csource ary;
		register_generator_for inam, "rb_iseq_load(#{rnam}, #{maybe_parent}, Qnil)"
	end

	# This is almost a Ruby-version iseq_build_body().
	def genfunc func, iseq, orignam, body, file, line, type
		labels_seen = Hash.new
		hdr = sprintf <<-end, type, orignam, file, line, func
/* %s %s */
/* from %s line %d */
rb_control_frame_t*
%s(rb_thread_t* t, rb_control_frame_t* r)
{
    VALUE* pc = r[0];
		end
		ftr = <<-end

    return r;
}
		end
		ic_idx = 0
		stmts = body.map do |i|
			case i
			when Symbol
				labels_seen.store i, true
				"\n%s:" % i.to_s
			when Numeric
#				sprintf %'#line %d "%s"\n', i, file
			when Array
				op = i.shift
				ta = YARVAOT::INSNS[op].first.zip i
				case op
				when :branchunless, :branchif, :jump
					m = /\d+/.match i.to_s
					s = if labels_seen.has_key? i[0]
							 "RUBY_VM_CHECK_INTS_TH(t);\n        "
						 else
							 ''
						 end
					b = sprintf <<-end, s, m[0], i[0]
						%scfp_pc(r) = pc + %d;
						goto %s;
					end
					case op
					when :branchunless
						b.gsub! %r/^\t+/, '        '
						"    if(!RTEST(*--cfp_sp(r))){\n%s    }" % b
					when :branchif
						b.gsub! %r/^\t+/, '        '
						"    if(RTEST(*--cfp_sp(r))){\n%s    }" % b
					when :jump
						b.gsub! %r/^\t+/, '    '
						b
					end
				# when :leave
				# 	'    /* yarvaot_insn_leave(t, r) */'
				else
					args = %w[t r]
					ta.each do |(t, a)|
						str = case t
								when 'ISEQ'
									if a.nil?
										'0' # null pointer
									else
										iseqval = recursive_transform a, iseq
										'DATA_PTR(%s)' % iseqval
									end
								when 'lindex_t', 'dindex_t', 'rb_num_t'
									a.to_s
								when 'IC'
									ic_idx += 1
									'yarvaot_get_ic(r, %d)' % ic_idx
								when 'OFFSET'
									robject2csource a # ??
								when 'CDHASH', 'VALUE'
									robject2csource a
								when 'GENTRY'
									# struct rb_global_entry*
									s = rstring2cstr a.to_s
									case s.size
									when 0
										raise ArgumentError, "must be a bug"
									when 1
										'(VALUE)rb_global_entry(rb_intern(%s))' % s[0][0]
									else
										raise ArgumentError, "Symbol #{a} too long"
									end
								when 'ID'
									# not the object, but its interned integer
									sym = robject2csource a
									sym.sub %/ID2SYM/, '' # ugly
								else
									raise TypeError, [op, ta].inspect
								end
						args << str
					end
					str = args.join ', '
					sprintf '    r = yarvaot_insn_%s(%s);', op, str
				end
			else
				raise TypeError, "unknown %p", i
			end
		end
		body = stmts.compact.join "\n"
		func = hdr + body + ftr
		@functions.push func
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
	# - Fixnums,  as  well  as  true,  false,  nil:  they  are  100%  statically
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
			get  = obj.val.to_s
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
			put  = 'rb_intern(%s)' % str.first.first
		when Encoding
			# Same as above; no GC please.
			str  = rstring2cstr obj.name
			type = 'rb_encoding*'
			qnam = namegen obj.name, type
			put  = 'rb_enc_find(%s)' % str.first.first
		when String
			if obj.empty?
				# empty strings do not even need encodings
				get = 'rb_str_new(0, 0)'
			else
				e   = robject2csource obj.encoding
				a   = rstring2cstr obj
				s   = a.shift
				if s[1] < 0.size * 3
					# Strings of small sizes are relatively cheap to create, because
					# they are embedded into the string struct.
					get = sprintf 'rb_enc_str_new(%s, %d, %s)', *s, e
				else
					qnam = namegen obj, type
					put  = sprintf 'rb_enc_str_new(%s, %d, %s)', *s, e
					put  = a.inject put do |r, (i, j)|
						sprintf 'rb_enc_str_buf_cat(%s, %s, %d, %s)', r, i, j, e
					end
				end
			end
		when Regexp
			opts = obj.options
			e    = robject2csource obj.encoding
			srcs = rstring2cstr obj.source
			if srcs.size > 1
				# FIXME
				raise ArgumentError, 'sorry, regexp too long (max 509 chars)'
			elsif obj.source.empty?
				# an empty regexp is not that chap I think...
				put = sprintf 'rb_enc_reg_new(0, 0, %s, %d)', e, opts
			else
				put = sprintf 'rb_enc_reg_new(%s, %d, %s, %d)', *srcs[0], e, opts
			end
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
				s = put.sub /\Arb_ary_new3\(\d+,\s+/, 'a'
				qnam = namegen s, type
			end
		when Hash
			# Hashes are not computable in a single expression...
			qnam = namegen 'hash_literal', type, :unique
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
	def namegen desired, type, realuniq = false, limit = 31
		str = namegen_internal desired, type, realuniq, limit - 2
		'y_' + str
	end

	def namegen_internal desired, type, realuniq, limit
		ary = @namedb[desired] # this creates new one if not.
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
			ary << [type, cand1]
			@namespace[cand1] = desired
			return cand1
		end
		u = Namespace.new_sha1 desired
		# An UUID is 128 bits length, while the infimum of maximal local variable
		# name length  in the  ANSI C is  31 characters.  The  canonical RFC4122-
		# style UUID stringization do not work here.
		bpc = 128.0 / limit
		radix = 2 ** bpc
		v = u.to_i.to_s radix.ceil
		namegen_internal v, type, realuniq, limit # try again
	end

	# Returns a 2-dimensional array [[str, len], [str, len], ... ]
	#
	# This is needed because Ruby's String#dump is different from C's.
	def rstring2cstr str
		# 509 is the  infimum of maximal length of string  literals that an ANSI-
		# conforming C compiler is required to understand.
		a = str.each_byte.each_slice 509
		a.map do |bytes|
			[
				'"' << bytes.map do |ord|
					case ord # this case statement is optimized
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
						case ord
						when 0x20 ... 0x7F then '%c' % ord
						else '\\x%x' % ord
						end
					end
				end.join << '"',
				bytes.size,
			]
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
