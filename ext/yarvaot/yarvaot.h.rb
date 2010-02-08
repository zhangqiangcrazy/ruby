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

/** @file yarvaot.h */

/* vm_{opts,core,insnhelper,exec}.h, as  well as eval_intern.h  and iseq.h, are
 * needed to ``properly'' make a AOT source, but we cheat instead. */
#ifndef RUBY_INSNHELPER_H
typedef struct rb_iseq_struct rb_iseq_t;
typedef struct rb_thread_struct rb_thread_t;
typedef VALUE* rb_control_frame_t; /* fake */
typedef long OFFSET;
typedef unsigned long rb_num_t;
typedef unsigned long lindex_t;
typedef unsigned long dindex_t;
typedef unsigned long GENTRY;
typedef rb_iseq_t* ISEQ;
typedef VALUE CDHASH;
typedef struct iseq_inline_cache_entry* IC;
typedef rb_control_frame_t* rb_insn_func_t(rb_thread_t* th, rb_control_frame_t* reg_cfp);

/**
 * hide_obj() seems not available worldwide
 *
 * @param[out] obj object to hide
 */
#define hide_obj(obj) (void)(RBASIC(obj)->klass = 0)

/**
 * rb_global_entry() is not exported either.
 *
 * @param[in] id  the id of globable variable in question
 * @returns       a valid pointer to a global variable entry.  creates one if not.
 */
extern struct rb_global_entry* rb_global_entry(ID id);

/**
 * Neither.
 *
 * @param[in] th thread
 */
extern void rb_vmdebug_debug_print_register(rb_thread_t *th);

/**
 * Neither.
 *
 * @param[in] array ISeq#to_a output array
 * @param[in] parent anothyer ISeq instance, or a Qnil
 * @param[opt] compile optoins
 * @returns a new ISeq instance
 */
extern VALUE rb_iseq_load(VALUE array, VALUE parent, VALUE opt);

/**
 * Neither.
 *
 * @param[in] iseqval  An ISeq object that wraps a rb_iseq_t
 * @returns  an evaluated value for iseqval's internal iseq
 */
extern VALUE rb_iseq_eval(VALUE iseqval);
#endif

% insns.each {|insn|

/**
 * category: <%= insn.comm[:c] %>
 *
<%= insn.comm[:e].gsub(/^/, " * ") %>
 *
 * @param[in]      th       the VM thread to run this instruction
 * @param[in, out] reg_cfp  current control frame
 * @returns                 an updated reg_cfp (maybe created in it)
 */
extern rb_control_frame_t* yarvaot_insn_<%=

insn.name

%>(rb_thread_t* th, rb_control_frame_t* reg_cfp<%=
   if(/^#define CABI_OPERANDS 1$/.match(extconfh))
       insn.opes.map {|(typ, nam)|
          (typ == "...") ? ", ..." : ", #{typ} #{nam}"
       }.join();
   else
       '';
   end
%>);
% };

/**
 * This  is yarvaot.so extension  library's entry  point.  BUT,  this extension
 * library is not useful  at all when you use from your  ruby script.  The main
 * reason  why this  lib  exists is  to  provide AOT-compiled  machine-readable
 * binary codes a bunch of runtime functionalities.  So, it's actually intended
 * to be linked using system-provided linker.
 */
extern void Init_yarvaot(void);

#ifndef RUBY_VM_CHECK_INTS_TH
/**
 * RUBY_VM_CHECK_INTS_TH was  actually a  macro when it's  in the  Ruby's core.
 * Now that you're in an extension  lib, you can't use that, because almost all
 * the macro body are touching opaque thread struct.
 *
 * @param[in,out] th   the  thread  in  question,  if  one  (or  two  or  more)
 *                     interrupts  are   on  a  queue  in   the  thread,  those
 *                     interrupts are consumed herein.
 */
extern void RUBY_VM_CHECK_INTS_TH(rb_thread_t* th);
#endif

/**
 * There's  neither an explicit  definition of  struct iseq_inline_cache_entry,
 * nor  a  way to  get  one  from a  control  frame  (before  that, there's  no
 * definition of rb_control_frame_struct...) And we  need one when we deal with
 * those opt_* instructions.  So there it  is, just return an opaque pointer to
 * nth IC entry of the given reg_cfp.
 *
 * @param[in] reg_cfp     the target control frame
 * @param[in] nth         index of the inline cache in question
 * @retval    NULL        no such IC
 * @retval    otherwise   a valid pointer to a inline cache entry.
 */
extern IC yarvaot_get_ic(rb_control_frame_t const* reg_cfp, int nth);

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
