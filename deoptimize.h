#ifndef RUBY_DEOPTIMIZE_H /* comments are in doxygen format, autobrief assumed. */
#define RUBY_DEOPTIMIZE_H 1

/**
 * ISeq deoptimization infrastructure, header file.
 *
 * @file      deoptimize.h
 * @author    Urabe, Shyouhei.
 * @date      Apr. 11th, 2016
 * @copyright Ruby's
 */

#include "ccan/list/list.h"     /* struct list_node */

struct rb_iseq_struct;          /* just forward decl */

/**
 * This is  a list node  that holds optimized  (to be deoptimized)  iseqs.  The
 * list head is located at rb_vm_t.
 *
 * @see struct rb_vm_struct
 * @see struct rb_iseq_constant_body
 */
struct iseq_to_deoptimize {
    const struct rb_iseq_struct *iseq; /**< target iseq */
    struct list_node node;             /**< double linked list pointers */
};

/**
 * Setup iseq to be eligible  for in-place optimization.  In-place optimization
 * here means  a kind of  optimizations such that instruction  sequence neither
 * shrink   nor   grow.    Such    optimization   can   be   done   on-the-fly,
 * instruction-by-instruction, with no need of modifying catch table.
 *
 * Optimizations themselves happen elsewhere.
 *
 * @param [in,out] i  target iseq struct.
 */
void iseq_prepare_to_deoptimize(const struct rb_iseq_struct *i)
    __attribute__((nonnull));

/**
 * Utility  inline function.   Preparation  need happen  only  once.  We  could
 * prepare every ISeq when they are generated  but not all ISeqs are subject to
 * change.  Preparing  ISeqs that would never  be optimized is a  waste of both
 * memory and time.  So we  delay preparation right before actual optimization.
 * This function should prepare an ISeq if it is not prepared yet.
 *
 * @param [out] iseq iseq struct to prepare.
 */
static inline void iseq_prepare_if_needed(const struct rb_iseq_struct *iseq)
    __attribute__((nonnull));

/**
 * Revert everything.
 *
 * We intentionally provide this  all-in-one API as deoptimization entry-point.
 * Each iseqs  could be  checked for  validness each  time, but  when something
 * happened  and deoptimization  was triggered,  it tends  to trigger  multiple
 * iseqs' deoptimization, not one-by-one.  So this API.
 *
 * FIXME: this does not interface with MVM and/or Guild.
 */
void rb_vm_deoptimize(void);

/**
 * An  iseq _can_  have  original_iseq.   That should  be  properly reset  upon
 * successful optimization/deoptimization transformations.
 *
 * @param [out] iseq target struct.
 */
#define ISEQ_RESET_ORIGINAL_ISEQ(iseq)          \
    RARRAY_ASET(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_ORIGINAL_ISEQ, Qfalse)

void
iseq_prepare_if_needed(const struct rb_iseq_struct *i)
{
    if (! i->body->iseq_deoptimized) {
        iseq_prepare_to_deoptimize(i);
    }
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
#endif
