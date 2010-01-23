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
#elif OPT_CALL_THREADED_CODE == 0
#undef OPT_CALL_THREADED_CODE
#define OPT_CALL_THREADED_CODE 1
#endif
#define DISPATCH_XXX 0
#include "vm_core.h"
#include "vm_insnhelper.h"
#include "vm_exec.h"
/* Some  tweaks are  needed because  vm_exec.h defines  some macros  harmful to
 * link against external functions. */
#undef INSN_ENTRY
#define INSN_ENTRY(nam)                         \
RUBY_EXTERN rb_control_frame_t*             	\
rb_vm_insn_ ## nam (                            \
    rb_thread_t *th,                            \
    rb_control_frame_t *reg_cfp                 \
) {
#include "vm_insnhelper.c"
#include "vm.inc"

void
Init_yarvaot(void)
{
    rb_define_module("YARVAOT");
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
