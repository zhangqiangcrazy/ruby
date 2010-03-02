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
#ifdef __GNUC__
#define UNLIKELY(expr) __builtin_expect((expr), 0)
#else
#define UNLIKELY(expr) (expr)
#endif
typedef struct rb_iseq_struct rb_iseq_t;
typedef VALUE* rb_control_frame_t; /* fake */
typedef rb_control_frame_t* rb_thread_t; /* fake */
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
RUBY_EXTERN struct rb_global_entry* rb_global_entry(ID id);

/**
 * Neither.
 *
 * @param[in] th thread
 */
RUBY_EXTERN void rb_vmdebug_debug_print_register(rb_thread_t *th);

/**
 * Neither.
 *
 * @param[in] array ISeq#to_a output array
 * @param[in] parent anothyer ISeq instance, or a Qnil
 * @param[opt] compile optoins
 * @returns a new ISeq instance
 */
RUBY_EXTERN VALUE rb_iseq_load(VALUE array, VALUE parent, VALUE opt);

/**
 * Neither.
 *
 * @param[in] iseqval  An ISeq object that wraps a rb_iseq_t
 * @returns  an evaluated value for iseqval's internal iseq
 */
RUBY_EXTERN VALUE rb_iseq_eval(VALUE iseqval);

#endif  /* RUBY_INSNHELPER_H */

/**
 * There is a  bit long story around  here.  A C compiler is  _not_ required to
 * understand a relatively  long string constant, but a  Ruby processor is.  So
 * when converting a Ruby string constant into C's, one cannot simply convert.
 *
 * Another pitfall  is the  encoding.  A Ruby  script tend  to be written  in a
 * multilingual encoding such as UTF-8, but that is totally out of control on a
 * C processor.  So a converter have to explicitly deal with them.
 */
struct yarvaot_lenptr_tag {
    size_t const nbytes;        /**< # of bytes vaild in ptr */
    void const* const ptr;      /**< opaque entry */
};

/**
 * This  is a  static  allocation  version of  a  ruby string,  to  be used  in
 * combination with yarvaot_quasi_iseq_tag().
 */
struct yarvaot_quasi_string_tag {
    char const* const encoding; /**< encoding string */
    struct yarvaot_lenptr_tag const* const entries; /**< actual entity */
};

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
RUBY_EXTERN rb_control_frame_t* yarvaot_insn_<%=

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
RUBY_EXTERN void Init_yarvaot(void);

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
RUBY_EXTERN void RUBY_VM_CHECK_INTS_TH(rb_thread_t* th);
#endif

/**
 * There's  neither an explicit  definition of  struct iseq_inline_cache_entry,
 * nor  a  way to  get  one  from a  control  frame  (before  that, there's  no
 * definition of rb_control_frame_struct...) And we  need one when we deal with
 * those opt_* instructions.  So there it  is, just return an opaque pointer to
 * IC entry of the given reg_cfp.
 *
 * @param[in] reg_cfp     the target control frame
 * @retval    NULL        no such IC
 * @retval    otherwise   a valid pointer to a inline cache entry.
 */
RUBY_EXTERN void* yarvaot_get_ic(rb_control_frame_t const* reg_cfp);

/**
 * An  ISeq's  IC  usage  is  normally  automatically  managed  by  the  Ruby's
 * NODE->ISeq compiler, but when you do a ISeq->C compilation that is no longer
 * possible, because no one can tell how  much ICs a C function will use.  This
 * function allocates at least _size_ counts of IC entries for given _iseqval_,
 * And to give it a proper _size_ argument is up to the C function.
 *
 * @param[out] reg_cfp  a control frame that points to a target iseq.
 * @param[in]  size     how many ICs will that iseqval use
 * @retval     TURE     allocation success
 * @retval     FALSE    allocation failure
 *
 * Apart  from  those  return   values  some  exceptions  might  raise  inside,
 * e.g. NoMemoryError.
 */
RUBY_EXTERN int yarvaot_set_ic_size(rb_control_frame_t* reg_cfp, size_t size);

/**
 * The size of a inline cache is also opaque.
 * @returns the size.
 *
 * GCC note: the return value of this function can be cached among invokations.
 * It is completely static.
 */
#ifdef GCC
__attribute__((__const__))
#endif
RUBY_EXTERN size_t yarvaot_sizeof_ic(void);

/**
 * An instruction pointer that points to  the head of this ISeq, is not visible
 * from outside of Ruby's core.
 *
 * @param[in] reg_cfp     the target control frame
 * @retval    NULL        no such ISeq
 * @retval    otherwise   a valid pointer to a inline cache entry.
 */
RUBY_EXTERN VALUE* yarvaot_get_pc(rb_control_frame_t const* reg_cfp);

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
