#if 1
#define __END__ /* void */
#else
top_srcdir = File.dirname(ARGV[1]);
require("erb");
require(ARGV[0]);

insns = RubyVM::InstructionsLoader.new({
    VPATH: [top_srcdir].extend(RubyVM::VPATH)
});

extconfh = File.read(ARGV[2]);

DATA.rewind();
ERB.new(DATA.read(), 0, "%-").run();
#endif
__END__

/* Ruby to C (and then,  to machine executable) compiler, originally written by
 * Urabe Shyouhei  <shyouhei@ruby-lang.org> during  2010.  See the  COPYING for
 * legal info. */
#include <ruby/ruby.h>
#include <ruby/encoding.h>
#include "eval_intern.h"
#include "iseq.h"
#include "vm_opts.h"
/* This AOT  compiler massively  uses Ruby's VM  feature called  "call threaded
 * code", so we have to enale that option here. */
#ifdef  OPT_CALL_THREADED_CODE
#undef  OPT_CALL_THREADED_CODE
#endif
#define OPT_CALL_THREADED_CODE 1

/* FIXME! inline chaches are to be implemented. */
#ifdef  OPT_INLINE_CONST_CACHE
#undef  OPT_INLINE_CONST_CACHE
#endif
#define OPT_INLINE_CONST_CACHE 0
#ifdef  OPT_INLINE_METHOD_CACHE
#undef  OPT_INLINE_METHOD_CACHE
#endif
#define OPT_INLINE_METHOD_CACHE 0

#include "vm_core.h"
#include "vm_insnhelper.h"
#include "vm_exec.h"
#include "yarvaot.h"

/* vm_insnhelper.c is actually a header file to be included, vital to build. */
#include "vm_insnhelper.c"

#define INSN_LABEL(l) l
#undef DEBUG_ENTER_INSN
#if defined VMDEBUG && VMDEBUG > 2
extern void rb_vmdebug_debug_print_register(rb_thread_t*);
#define DEBUG_ENTER_INSN(nam) fprintf(stderr, "%18s @ %p", nam, reg_cfp);       \
    rb_vmdebug_debug_print_register(th)
#else
#define DEBUG_ENTER_INSN(nam)   /* void */
#endif

static VALUE gen_insns_info(void);
static VALUE rb_str_new_from_quasi_string(struct yarvaot_quasi_string_tag const* q);
static VALUE rb_sym_new_from_quasi_string(struct yarvaot_quasi_string_tag const* q);
#ifdef __GNUC__
__attribute__((__const__, __always_inline__))
#endif
static inline char const* yarvaot_iseq_type_name(enum yarvaot_iseq_type_tag t);
#ifdef __GNUC__
__attribute__((__const__, __always_inline__))
#endif
static inline char const* yarvaot_catch_type_name(enum yarvaot_catch_type_tag t);
static VALUE yarvaot_new_array_of_symbols(struct yarvaot_quasi_string_tag const* a);
static VALUE yarvaot_geniseq_genargs(struct yarvaot_quasi_iseq_tag const* q);
static VALUE yarvaot_geniseq_gencatch(struct yarvaot_quasi_catch_table_entry_tag const* q);
static VALUE yarvaot_geniseq_genbody(struct yarvaot_quasi_iseq_tag const* q);

% insns.each {|insn|
#line <%= _erbout.lines.to_a.size + 1 %> "yarvaot.c"

rb_control_frame_t*
yarvaot_insn_<%= insn.name %>(
    rb_thread_t* th<% -%>
%   if(/^#define CABI_OPERANDS 1$/.match(extconfh))
%       insn.opes.map {|(typ, nam)|
%           if(typ == "...")
,
     ...<% -%>
%           else
,
    <%= typ %> <%= nam -%>
%           end;
%       }
%   end
)
{
    rb_control_frame_t* reg_cfp = th->cfp;
    /* make_header_prepare_stack omitted */
    /* make_header_stack_val */
%   vars = insn.opes + insn.pops + insn.defopes.map() {|ent| ent[0]; };
%   insn.rets.each() {|(typ, nam)|
%       if(vars.all? {|(vtyp, vnam)| vnam != nam } && nam != "...")
    <%= typ %> <%= nam %>;
%       end
%   }
    /* make_header_default_operands ommited */
%   if(/^#define CABI_OPERANDS 1$/.match(extconfh))
    /* make_header_operands moved to machine ABI */
%   else
    /* make_header_operands */
%       insn.opes.each_with_index {|(typ, nam), i|
%           if(typ == "...")
%               break;
%           else
    <%= typ %> <%= nam %> = (<%= typ %>)GET_OPERAND(<%= i + 1 %>);
%           end
%       }
%   end
    /* make_header_temporary_vars */
%   insn.tvars.each() {|(typ, nam)|
        <%= typ %> <%= nam %>;
%   }
    /* make_header_stack_pops (in reverse order) */
%   n = 0;
%   pops = Array.new();
%   vars = insn.pops;
%   vars.each() {|(typ, nam, rst)|
%       break if(nam == "...");
%       if(rst)
%           pops << "#{typ} #{nam} = SCREG(#{rst});";
%       else
%           pops << "#{typ} #{nam} = TOPN(#{n});";
%           n += 1;
%       end;
%   }
%   popn = n;
    <%= pops.reverse.join("\n    ")%>
    /* make_header_debug */
    DEBUG_ENTER_INSN("<%= insn.name%>");
    /* make_header_pc */
    ADD_PC(1 + <%=
        insn.opes.inject(0) {|r, (t, n)|
            break(r) if t == "..."
            r + 1
        }
    %>);
    PREFETCH(GET_PC());
    /* make_header_popn */
%   if(popn > 0)
    POPN(<%= popn %>);
%   end;
    /* make_header_defines omitted */
    /* make_header_analysts */
    USAGE_ANALYSIS_INSN(BIN(<%= insn.name %>));
%   insn.opes.each_with_index() {|(typ, nam), j|
    USAGE_ANALYSIS_OPERAND(BIN(<%= insn.name %>), <%= j %>, <%= nam %>);
%   }    
    {
%   b = insn.body.gsub(/^\s*/, '\\&    ').rstrip
%   if(line = insn.body.instance_variable_get(:"@line_no"))
%       file = insn.body.instance_variable_get(:"@file");
#line <%= line + 1 %> "<%= file %>"
%   end;
<%= b %>
#line <%= _erbout.lines.to_a.size + 1 %> "yarvaot.c"
    }
    /* make_footer_stack_val */
%   n = insn.rets.reverse.inject(0) {|r, (typ, nam, rst)|
%       break(r) if nam == "...";
%       r if rst
%       r + 1
%   }
    CHECK_STACK_OVERFLOW(reg_cfp, <%= n %>);
%   insn.rets.reverse_each() {|(typ, nam, rst)|
%       if rst
    SCREG(<%= rst %>) = nam;
%       elsif nam == "..."
%           break;
%       else
    PUSH(<%= nam %>);
%       end;
%   }
    /* make_footer_default_operands omitted */
    /* make_footer_undefs omitted */
    return reg_cfp;
}

% };

static VALUE
gen_insns_info(void)
{
%data = Marshal.dump insns.inject({}) {|r, i|
%   r[i.name.intern] = {
%       opes: i.opes,
%       pops: i.pops,
%       rets: i.rets,
%       body: i.body,
%       comm: i.comm,
%   }
%   r
%}
    unsigned char data[] = {
%data.each_byte.each_slice(12).each {|bytes|
        <%= bytes.map {|i| "%#04x" % i }.join(", ") %>,
%}
    };
    size_t size = <%= data.bytesize %>;
    rb_encoding* binary = rb_ascii8bit_encoding();
    VALUE str = rb_enc_str_new((char*)data, size, binary);
    VALUE ret = rb_marshal_load(str);
    return ret;
}

void*
yarvaot_get_ic(rb_control_frame_t const* reg_cfp)
{
    rb_iseq_t* iseq = 0;
    struct iseq_inline_cache_entry* ic_entries = 0;

    if((iseq = reg_cfp->iseq) == NULL) return NULL;
    if((ic_entries = iseq->ic_entries) == NULL) return NULL;
    return ic_entries;
}

size_t
yarvaot_sizeof_ic(void)
{
    return sizeof (struct iseq_inline_cache_entry);
}

VALUE*
yarvaot_get_pc(rb_control_frame_t const* reg_cfp)
{
    rb_iseq_t* iseq = 0;

    if((iseq = reg_cfp->iseq) == NULL)
        return NULL;
    else
        return iseq->iseq_encoded;
}

#undef RUBY_VM_CHECK_INTS_TH
void
RUBY_VM_CHECK_INTS_TH(rb_thread_t* th)
{
    if(th->interrupt_flag)
        rb_threadptr_execute_interrupts(th);
}

void
Init_yarvaot(void)
{
    VALUE rb_mYARVAOT = rb_define_module("YARVAOT");
    rb_define_const(rb_mYARVAOT, "INSNS", gen_insns_info());
}

VALUE
vrb_enc_str_new(char const* enc, ...)
{
    va_list ap;
    rb_encoding* e = rb_enc_find(enc);
    VALUE ret = rb_str_buf_new(0);
    void const* p = 0;
    size_t s = 0;
    va_start(ap, enc);
    for(;;) {
        p = va_arg(ap, void const*);
        if(!p) return ret;
        s = va_arg(ap, size_t);
        if(!s) return ret;
        ret = rb_enc_str_buf_cat(ret, p, (long)s, e);
    }
    /* NOTREACHED */
    va_end(ap);
}

VALUE
rb_str_new_from_quasi_string(struct yarvaot_quasi_string_tag const* q)
{
    rb_encoding* e = rb_enc_find(q->encoding);
    VALUE ret = rb_str_buf_new(0);
    struct yarvaot_lenptr_tag const* p = 0;
    if(q)
        for(p = q->entries; p->ptr; p++)
            ret = rb_enc_str_buf_cat(ret, p->ptr, p->nbytes, e);
    return ret;
}

VALUE
rb_sym_new_from_quasi_string(struct yarvaot_quasi_string_tag const* q)
{
    return rb_str_intern(rb_str_new_from_quasi_string(q));
}

VALUE
yarvaot_new_array_of_symbols(struct yarvaot_quasi_string_tag const* a)
{
    VALUE ret = rb_ary_new();
    if(a) 
        for(; a->entries; a++)
            ret = rb_ary_push(ret, rb_sym_new_from_quasi_string(a));
    return ret;
}

char const*
yarvaot_iseq_type_name(enum yarvaot_iseq_type_tag t)
{
    /* this kind  of C  source code can  be extremely  fast when compiled  by a
     * properly  optimizing  C  compiler,  so  it  is  worth  remembering  this
     * idiom. */
    switch(t) {
#define c(x, y) case x: return #y
        c(ISEQ_TYPE_TOP,top);
        c(ISEQ_TYPE_METHOD,        method);
        c(ISEQ_TYPE_BLOCK,         block);
        c(ISEQ_TYPE_CLASS,         class);
        c(ISEQ_TYPE_RESCUE,        rescue);
        c(ISEQ_TYPE_ENSURE,        ensure);
        c(ISEQ_TYPE_EVAL,          eval);
        c(ISEQ_TYPE_MAIN,          main);
        c(ISEQ_TYPE_DEFINED_GUARD, defined_guard);
#undef c
    }
    rb_bug("unknown ISeq type %d", (int)t);
    /* NOTREACHED */
    return 0;
}

char const*
yarvaot_catch_type_name(enum yarvaot_catch_type_tag t)
{
    switch(t) {
#define c(x, y) case x: return #y
        c(CATCH_TYPE_RESCUE, rescue);
        c(CATCH_TYPE_ENSURE, ensure);
        c(CATCH_TYPE_RETRY,  retry);
        c(CATCH_TYPE_BREAK,  break);
        c(CATCH_TYPE_REDO,   redo);
        c(CATCH_TYPE_NEXT,   next);
#undef c
    }
    rb_bug("unknown catch type %d", (int)t);
    /* NOTREACHED */
    return 0;
}

VALUE
yarvaot_geniseq_genargs(struct yarvaot_quasi_iseq_tag const* q)
{
    if(q->args.simple) {
        return INT2FIX(q->args.argc);
    }
    else {
        VALUE ret = rb_ary_new();
        ret = rb_ary_push(ret, LONG2FIX(q->args.argc));
        ret = rb_ary_push(ret, yarvaot_new_array_of_symbols(q->args.opts));
        ret = rb_ary_push(ret, LONG2FIX(q->args.post_len));
        ret = rb_ary_push(ret, LONG2FIX(q->args.post_start));
        ret = rb_ary_push(ret, LONG2FIX(q->args.rest));
        ret = rb_ary_push(ret, LONG2FIX(q->args.block));
        ret = rb_ary_push(ret, LONG2FIX(q->args.simple));
        return ret;
    }
}

VALUE
yarvaot_geniseq_gencatch(struct yarvaot_quasi_catch_table_entry_tag const* q)
{
    /* Exception table is an array of arrays. */
    VALUE ret = rb_ary_new();
    if(!q) return ret;
    for(; q->start; q++) {
        VALUE ent = rb_ary_new();
        ID tid = rb_intern(yarvaot_catch_type_name(q->type));
        ent = rb_ary_push(ent, ID2SYM(tid));
        ent = rb_ary_push(ent, yarvaot_geniseq(q->iseq));
        ent = rb_ary_push(ent, ID2SYM(rb_intern(q->start)));
        ent = rb_ary_push(ent, ID2SYM(rb_intern(q->end)));
        ent = rb_ary_push(ent, ID2SYM(rb_intern(q->count)));
        ent = rb_ary_push(ent, LONG2FIX(q->sp));
        ret = rb_ary_push(ret, ent);
    }
    return ret;
}

VALUE
yarvaot_geniseq_genbody(struct yarvaot_quasi_iseq_tag const* q)
{
    char const* const* p = 0;
    VALUE i    = Qundef;
    VALUE ret  = rb_ary_new();
    VALUE nop  = rb_ary_new3(1, ID2SYM(rb_intern("nop")));
    VALUE occf = rb_ary_new3(2, ID2SYM(rb_intern("opt_call_c_function")),
                             ULONG2NUM((unsigned long)q->impl));
    for(p = q->template; ; p++)
        if(*p == 0)             /* for nop */
            ret = rb_ary_push(ret, nop);
        else if(**p == 0)       /* for occf */
            ret = rb_ary_push(ret, occf);
        else if(MEMCMP(*p, "end", char, 3) == 0) /* end mark */
            return ret;
        else if(MEMCMP(*p, "label_", char, 6) == 0)
            ret = rb_ary_push(ret, ID2SYM(rb_intern(*p)));
        else if(RTEST(i = rb_cstr_to_inum(*p, 0, 0))) /* lineno */
            ret = rb_ary_push(ret, i);
        else                    /* ?? what ?? */
            rb_raise(rb_eTypeError, "unknown: %s", *p);
}

VALUE
yarvaot_geniseq(struct yarvaot_quasi_iseq_tag const* q)
{
    if(!q) {
        /* this can be the case where exception table holds no body */
        return Qnil;
    }
    else {
        VALUE magic  = vrb_enc_str_new("US-ASCII",
            "YARVInstructionSequence/SimpleDataFormat", 40, 0);
        VALUE major  = INT2FIX(1);
        VALUE minor  = INT2FIX(2);
        VALUE teeny  = INT2FIX(1);
        VALUE intro  = Qnil;        /* seems not used at all */
        VALUE name   = rb_str_new_from_quasi_string(&q->name);
        VALUE file   = rb_str_new_from_quasi_string(&q->filename);
        VALUE lineno = LONG2FIX(q->lineno);
        VALUE type   = ID2SYM(rb_intern(yarvaot_iseq_type_name(q->type)));
        VALUE locals = yarvaot_new_array_of_symbols(q->locals);
        VALUE args   = yarvaot_geniseq_genargs(q);
        VALUE excs   = yarvaot_geniseq_gencatch(q->catches);
        VALUE body   = yarvaot_geniseq_genbody(q);
        VALUE to_a   = rb_ary_new3(13,
                                   magic, major, minor, teeny,
                                   intro, name, file, lineno, type,
                                   locals, args, excs, body);
        return rb_iseq_load(to_a, Qnil, Qnil);
    }
}

/*
 * Local Variables:
 * mode: C
 * coding: utf-8-unix
 * indent-tabs-mode: nil
 * tab-width: 8
 * fill-column: 79
 * default-justification: full
 * c-file-style: "Ruby"
 * c-doc-comment-style: javadoc
 * End:
 */
