#ifndef RUBY_DEOPTIMIZE_H
#define RUBY_DEOPTIMIZE_H 1

/**
 * ISeq deoptimization infrastructure, header file.
 *
 * @file      deoptimize.h
 * @author    Urabe, Shyouhei.
 * @date      Apr. 11th, 2016
 * @copyright Ruby's
 */

#include <stdbool.h>
#include <stdint.h>
#include "internal.h"
#include "vm_core.h"

/**
 * Main struct to  hold deoptimization infrastructure.  It basically  is a pair
 * of original iseq  and its length.  This struct is  expected to frequently be
 * created then removed, along with the progress of program execution.
 */
struct iseq_to_deoptimize {
    const rb_serial_t created_at;  /**< creation timestamp */
    const uintptr_t *restrict ptr; /**< deoptimized raw body */
};

struct rb_iseq_struct; /* just forward decl */

/**
 * Setup iseq to be eligible  for in-place optimization.  In-place optimization
 * here means  a kind of  optimizations such that instruction  sequence neither
 * shrink   nor   grow.    Such    optimization   can   be   done   on-the-fly,
 * instruction-by-instruction, with no need of modifying catch table.
 *
 * Optimizations themselves happen elsewhere.
 *
 * @param [in,out] i  target iseq struct.
 * @param [in]     t  creation time stamp.
 */
void iseq_prepare_to_deoptimize(const struct rb_iseq_struct *i, rb_serial_t t);

/**
 * Deallocates  an  iseq_to_deoptimize  struct.  Further  actions  against  the
 * argument pointer are illegal, can cause fatal failure of any kind.
 *
 * @warning  It  does _not_  deallocate  optimized  pointer because  that  were
 * created before the argument was created.  It does not have their ownership.
 *
 * @param [in] i target struct to free.
 */
void iseq_to_deoptimize_free(const struct iseq_to_deoptimize *i);

/**
 * Calculate memory size of given structure, in bytes.
 *
 * @param [in] b target's body
 * @return size of the struct.
 */
size_t iseq_to_deoptimize_memsize(const struct rb_iseq_constant_body *b);

/**
 * Revert  all optimizations  that was  done before.   Iterates over  optimized
 * sequences to  check for stale  ones, and does the  deoptimization operations
 * over found ones.
 *
 * @param [out] vm global vm structure.
 */
void rb_purge_stale_iseqs(const struct rb_vm_struct *vm);

/**
 * An  iseq _can_  have  original_iseq.   That should  be  properly reset  upon
 * successful optimization/deoptimization transformations.
 *
 * @param [out] iseq target struct.
 */
#define ISEQ_RESET_ORIGINAL_ISEQ(iseq)          \
    RARRAY_ASET(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_ORIGINAL_ISEQ, Qfalse)

#endif
