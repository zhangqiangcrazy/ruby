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

/** This should not be here... */
enum yarvaot_catch_type_tag {
    CATCH_TYPE_RESCUE = ((int)INT2FIX(1)),
    CATCH_TYPE_ENSURE = ((int)INT2FIX(2)),
    CATCH_TYPE_RETRY  = ((int)INT2FIX(3)),
    CATCH_TYPE_BREAK  = ((int)INT2FIX(4)),
    CATCH_TYPE_REDO   = ((int)INT2FIX(5)),
    CATCH_TYPE_NEXT   = ((int)INT2FIX(6))
};

/** This should not be here... */
enum yarvaot_iseq_type_tag {
    ISEQ_TYPE_TOP           = INT2FIX(1),
    ISEQ_TYPE_METHOD        = INT2FIX(2),
    ISEQ_TYPE_BLOCK         = INT2FIX(3),
    ISEQ_TYPE_CLASS         = INT2FIX(4),
    ISEQ_TYPE_RESCUE        = INT2FIX(5),
    ISEQ_TYPE_ENSURE        = INT2FIX(6),
    ISEQ_TYPE_EVAL          = INT2FIX(7),
    ISEQ_TYPE_MAIN          = INT2FIX(8),
    ISEQ_TYPE_DEFINED_GUARD = INT2FIX(9)
};

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

#define yqst struct yarvaot_quasi_string_tag /**< temporary rename */

/**
 * This is a ``quasi'' instruction  sequence, which can then be converted using
 * yarvaot_geniseq().
 *
 * And beware  of those tactically  placed const qualifiers...  This  struct is
 * designed to be  totally statically allocated, which makes  a compiled binary
 * faster.
 */
struct yarvaot_quasi_iseq_tag {
    enum yarvaot_iseq_type_tag const type; /**< type of this iseq */
    yqst const name;            /**< iseq name */
    yqst const filename;        /**< where was it from */
    long const lineno;          /**< where was it from */
    yqst const* const locals;   /**< local variables */
    struct {                    /**< args */
        long const argc;        /**< argc */
        yqst const* const opts; /**< arg_opts */
        long const post_len;    /**< arg_post_len */
        long const post_start;  /**< arg_post_start */
        long const rest;        /**< arg_rest */
        long const block;       /**< arg_block */
        long const simple;      /**< arg_simple */
    } const args;               /**< args */
    struct yarvaot_quasi_catch_table_entry_tag const* const catches;
    char const* const* const template;
    rb_insn_func_t* const impl;  /**< body */
};

/**
 * This is a static allocation version  of iseq exception tables, to be used in
 * combination with yarvaot_quasi_iseq_tag().
 */
struct yarvaot_quasi_catch_table_entry_tag {
    enum yarvaot_catch_type_tag const type;          /**< type */
    struct yarvaot_quasi_iseq_tag const* const iseq; /**< body */
    char const* const start;                         /**< label start */
    char const* const end;                           /**< label end */
    char const* const count;                         /**< label count */
    long const sp;                                   /**< sp */
};

#undef yqst

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

%>(rb_thread_t* th<%=
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

/**
 * This  is a  helper function,  to  ease a  creation of  relatively long  m17n
 * string.  According to the ISO C, a  string literal can be at most 509 chars,
 * and a function  can have at most 31  arguments.  So this way you  can make a
 * string of  max 7,635 chars length.   Note however, that the  term `chars' is
 * used here in the sense of C.  Your milage will vary with your encoding.
 *
 * @sa struct yarvaot_quasi_string_tag
 *
 * @param[in] enc  encoding string.
 * @param[in] ...  a series of void*, size_t, void*, size_t, ..., terminates 0.
 * @returns        a Ruby string of encoding enc.
 */
RUBY_EXTERN VALUE vrb_enc_str_new(char const* enc, ...);

/**
 * Creates a ``real'' ISeq from a quasi-iseq.
 *
 * @param[in] quasi  a template.
 * @returns          a generated ISeq's iseqval.
 */
RUBY_EXTERN VALUE yarvaot_geniseq(struct yarvaot_quasi_iseq_tag const* quasi);

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
