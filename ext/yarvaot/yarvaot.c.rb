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

% insns.each {|insn|
#line <%= _erbout.lines.to_a.size + 1 %> "yarvaot.c"

rb_control_frame_t*
yarvaot_insn_<%= insn.name %>(
    rb_thread_t* th,
    rb_control_frame_t* reg_cfp<% -%>
%if(/^#define CABI_OPERANDS 1$/.match(extconfh))
%   insn.opes.map {|(typ, nam)|
%       if (typ == "...")
,
     ...<% -%>
%       else
,
    <%= typ %> <%= nam -%>
%       end;
%   }
%end
)
{
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
    struct {
        char const* const name;
        char const* const operands;
        int const instruction_size;
        int const icoperands_num;
        int const stack_push_num;
    } const insns_info[] = {
%   insns.each() {|insn|
%       n = insn.name;
%       o = insn.opes.map() {|(typ, nam)| typ }.join(", ");
%       i = insn.opes.size + 1;
%       c = insn.opes.select {|typ, nam| typ == "IC"}.count();
%       s = insn.rets.size;
        { "<%= n %>", "<%= o %>", <%= i %>, <%= c %>, <%= s %>, },
%   }
        { 0, 0, 0, 0, }, /* end mark */
    };

    VALUE ret = rb_hash_new();
    int i;
    for (i = 0; insns_info[i].name; i++) {
        VALUE key = ID2SYM(rb_intern(insns_info[i].name));
        VALUE val = rb_ary_new();
        VALUE op1 = rb_str_new_cstr(insns_info[i].operands);
        VALUE op2 = rb_str_split(op1, ", ");
        rb_ary_push(val, op2);
        rb_ary_push(val, INT2FIX(insns_info[i].instruction_size));
        rb_ary_push(val, INT2FIX(insns_info[i].icoperands_num));
        rb_ary_push(val, INT2FIX(insns_info[i].stack_push_num));
        rb_hash_aset(ret, key, val);
    }
    return ret;
}

struct iseq_inline_cache_entry*
yarvaot_get_ic(
    rb_control_frame_t const* reg_cfp,
    int nth)
{
    rb_iseq_t* iseq = 0;
    struct iseq_inline_cache_entry* ic_entries = 0;

    if(nth < 0) return NULL;
    if((iseq = reg_cfp->iseq) == NULL) return NULL;
    if((ic_entries = iseq->ic_entries) == NULL) return NULL;
    if(iseq->ic_size < nth) return NULL;
    return &ic_entries[nth];
}

#undef RUBY_VM_CHECK_INTS_TH
void
RUBY_VM_CHECK_INTS_TH(rb_thread_t* th)
{
    if (th->interrupt_flag)
        rb_threadptr_execute_interrupts(th);
}

void
Init_yarvaot(void)
{
    VALUE rb_mYARVAOT = rb_define_module("YARVAOT");
    rb_define_const(rb_mYARVAOT, "INSNS", gen_insns_info());
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
