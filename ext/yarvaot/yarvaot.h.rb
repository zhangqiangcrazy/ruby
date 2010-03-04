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
#include "eval_intern.h"
#include "iseq.h"
#include "vm_opts.h"
/* This AOT  compiler massively  uses Ruby's VM  feature called  "call threaded
 * code", so we have to enable that option here. */
#ifdef  OPT_CALL_THREADED_CODE
#undef  OPT_CALL_THREADED_CODE
#endif
#define OPT_CALL_THREADED_CODE 1

#include "vm_core.h"
#include "vm_insnhelper.h"
#include "vm_exec.h"

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
