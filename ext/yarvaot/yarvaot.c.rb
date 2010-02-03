#if 1
#define __END__ /* void */
#else
top_srcdir = File.dirname(ARGV[1]);
require("erb");
require(ARGV[0]);

insns = RubyVM::InstructionsLoader.new({
    VPATH: [top_srcdir].extend(RubyVM::VPATH)
});

DATA.rewind();
ERB.new(DATA.read(), 0, '%').run();
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
#ifndef OPT_CALL_THREADED_CODE
#define OPT_CALL_THREADED_CODE 1
#elif   OPT_CALL_THREADED_CODE == 0
#undef  OPT_CALL_THREADED_CODE
#define OPT_CALL_THREADED_CODE 1
#endif
#include "vm_core.h"
#include "vm_insnhelper.h"
#include "vm_exec.h"
#include "yarvaot.h"

/* vm_insnhelper.c is actually a header file to be included, vital to build. */
#include "vm_insnhelper.c"

#define INSN_LABEL(l) l

% insns.each {|insn|
#line <%= __LINE__ %> "yarvaot.c"

rb_control_frame_t*
yarvaot_insn_<%= insn.name %>(
    rb_thread_t* th,
    rb_control_frame_t* reg_cfp<%=
    insn.opes.map {|(typ, nam)|
        (typ == "...") ? ",\n     ..." : ",\n    #{typ} #{nam}"
    }.join%>)
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
    /* make_header_operands moved to machine ABI */
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
%   b = insn.body.gsub(/^/, "    ").rstrip
%   if(line = insn.body.instance_variable_get(:"@line_no"))
%       file = insn.body.instance_variable_get(:"@file");
#line <%= line + 1 %> "<%= file %>"
%   end;
<%= b %>
#line <%= __LINE__ %> "yarvaot.c"
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
        VALUE key = rb_str_new_cstr(insns_info[i].name);
        VALUE val = rb_ary_new();
        VALUE op1 = rb_str_new_cstr(insns_info[i].operands);
        VALUE op2 = rb_str_split(op1, ", ");
        rb_ary_push(val, op2);
        rb_ary_push(val, INT2FIX(insns_info[i].instruction_size));
        rb_ary_push(val, INT2FIX(insns_info[i].icoperands_num));
        rb_ary_push(val, INT2FIX(insns_info[i].stack_push_num));
    }
    return ret;
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
