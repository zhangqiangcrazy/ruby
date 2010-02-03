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
Process.exit();
#endif
__END__
#ifndef RUBY_EXT_YARVAOT_H
#define RUBY_EXT_YARVAOT_H 1
/* Ruby to C (and then,  to machine executable) compiler, originally written by
 * Urabe Shyouhei  <shyouhei@ruby-lang.org> during  2010.  See the  COPYING for
 * legal info. */
#include <ruby/ruby.h>
#include <ruby/vm.h>

/* vm_{opts,core,insnhelper,exec}.h, as  well as eval_intern.h  and iseq.h, are
 * needed to ``properly'' make a AOT source, but we cheat instead. */
#ifndef RUBY_INSNHELPER_H
typedef struct rb_iseq_struct rb_iseq_t;
typedef struct rb_thread_struct rb_thread_t;
typedef struct rb_control_frame_struct rb_control_frame_t; /* fake */
typedef long OFFSET;
typedef unsigned long rb_num_t;
typedef unsigned long lindex_t;
typedef unsigned long dindex_t;
typedef unsigned long GENTRY;
typedef rb_iseq_t* ISEQ;
typedef VALUE CDHASH;
typedef struct iseq_inline_cache_entry* IC;
typedef rb_control_frame_t* rb_insn_func_t(rb_thread_t* th, rb_control_frame_t* reg_cfp);

/* hide_obj() seems not available worldwide */
#define hide_obj(obj) (void)(RBASIC(obj)->klass = 0)
/* rb_global_entry() is not exported either. */
extern struct rb_global_entry* rb_global_entry(ID);

#endif

% insns.each {|insn|
extern rb_control_frame_t* yarvaot_insn_<%=

insn.name

%>(rb_thread_t* th, rb_control_frame_t* reg_cfp<%=

insn.opes.map {|(typ, nam)|
     (typ == "...") ? ", ..." : ", #{typ} #{nam}"
}.join

%>);
% };

extern void Init_yarvaot(void);
extern VALUE rb_iseq_load(VALUE data, VALUE parent, VALUE opt);
extern struct iseq_inline_cache_entry* rb_yarvaot_get_ic(rb_control_frame_t* reg_cfp, int nth);

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
#endif /* RUBY_EXT_YARVAOT_H */
