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
#include "insns_info.inc"

static VALUE
gen_insns_info(void)
{
    VALUE ret = rb_hash_new();
    int n = sizeof insn_name_info / sizeof insn_name_info[0];
    int i;
    for(i=0; i<n; i++) {
        VALUE key = ID2SYM(rb_intern(insn_name_info[i]));
        VALUE val = rb_ary_new();
        const char* types = insn_operand_info[i];
        int len = insn_len_info[i];
        int iclen = insn_iclen_info[i];
        rb_ary_push(val, rb_str_new_cstr(types));
        rb_ary_push(val, INT2FIX(len));
        rb_ary_push(val, INT2FIX(iclen));
        rb_hash_aset(ret, key, val);
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
