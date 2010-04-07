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
#define RUBY_EXPORT             /* ??? */
#include <ruby/ruby.h>
#include <ruby/encoding.h>
#include "gc.h"
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

% insns.each {|insn|
#line <%= _erbout.lines.to_a.size + 1 %> "yarvaot.c"

rb_control_frame_t*
yarvaot_insn_<%= insn.name %>(
    rb_thread_t* th<% -%>
%   if(/^#define CABI_PASS_CFP 1$/.match(extconfh))
,
    rb_control_frame_t* reg_cfp<% -%>
%   end
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
%   if(!/^#define CABI_OPERANDS 1$/.match(extconfh))
    rb_control_frame_t* reg_cfp = th->cfp;
%   end
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
%       defopes: i.defopes,
%       tvars: i.tvars,
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

static VALUE
gen_headers(void)
{
%data = Marshal.dump %w[
%  debug.h
%  eval_intern.h
%  id.h
%  iseq.h
%  method.h
%  node.h
%  thread_pthread.h
%  thread_win32.h
%  vm_core.h
%  vm_core.h
%  vm_exec.h
%  vm_insnhelper.c
%  vm_insnhelper.h
%  vm_opts.h
%  vm_opts.h
%].inject({}) {|r, i|
%  begin
%     r[i] = File.read(top_srcdir + '/' + i)
%  rescue Errno::ENOENT
%     r[i] = File.read(Dir.getwd + '/../../' + i)
%  end
%  r
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

void
Init_yarvaot(void)
{
    VALUE rb_mYARVAOT = rb_define_module("YARVAOT");
    rb_define_const(rb_mYARVAOT, "INSNS", gen_insns_info());
    rb_define_const(rb_mYARVAOT, "HEADERS", gen_headers());
}

int
yarvaot_set_ic_size(rb_control_frame_t* reg_cfp, size_t size)
{
    rb_iseq_t* iseq = 0;
    void* p = 0;
    if(!reg_cfp)
        return FALSE;
    else if(!(iseq = reg_cfp->iseq))
        return FALSE;
    else if(size <= iseq->ic_size)
        return TRUE;
    else if(!(p = xcalloc(size, sizeof(struct iseq_inline_cache_entry))))
        return FALSE;
    /* else */
    RUBY_FREE_UNLESS_NULL(iseq->ic_entries);
    iseq->ic_size = size;
    iseq->ic_entries = p;
    return TRUE;
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
