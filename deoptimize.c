/* comments are in doxygen format, autobrief assumed. */

/**
 * ISeq deoptimization infrastructure, implementation.
 *
 * @file      deoptimize.c
 * @author    Urabe, Shyouhei.
 * @date      Apr. 11th, 2016
 * @copyright Ruby's
 */

#include "ruby/config.h"
#include <stddef.h>             /* size_t */
#include "vm_core.h"            /* rb_iseq_t */
#include "iseq.h"               /* ISEQ_ORIGINAL_ISEQ */
#include "deoptimize.h"

/* FIXME: This file assumes that there is one and only VM, and can be reachable
 * via ruby_current_vm.  This situation holds now but is subject to change in a
 * future (when _ko1 merges his Guild feature). */
extern struct rb_vm_struct *ruby_current_vm;

typedef struct iseq_to_deoptimize target_t;
typedef struct rb_iseq_constant_body body_t;

/**
 * Does the deoptimization process.
 *
 * @param [out] iseq iseq struct to deoptimize.
 */
static void iseq_deoptimize(const rb_iseq_t *iseq);

/**
 * Inverse  of iseq_deoptimize;  that  is, allocate  buffer  and store  vanilla
 * sequence onto there.
 *
 * @param [out] iseq iseq struct to deoptimize.
 */
static void iseq_evacuate(const rb_iseq_t *i);

/**
 * List constructor.
 *
 * @param [in] iseq iseq struct to deoptimize.
 * @return allocated new list node.
 */
static target_t *list_alloc(const rb_iseq_t *i);

target_t *
list_alloc(const rb_iseq_t *i)
{
    target_t *restrict d = ruby_xmalloc(sizeof(d));
    d->iseq              = i;
    list_node_init(&d->node);
    return d;
}

void
iseq_evacuate(const rb_iseq_t *i)
{
    /* Note how this function resembles iseq_deoptimize() below */
    body_t *restrict b      = i->body;
    size_t s                = sizeof(VALUE) * b->iseq_size;
    const VALUE *restrict x = b->iseq_encoded;
    const VALUE *restrict y = ruby_xmalloc(s);

    memcpy((void *)y, x, s);
    b->iseq_deoptimized     = y;
}

void
iseq_deoptimize(const rb_iseq_t *i)
{
    /* Note how this function resembles iseq_evacauate() above */
    body_t *restrict b      = i->body;
    size_t s                = sizeof(VALUE) * b->iseq_size;
    const VALUE *restrict x = b->iseq_encoded;
    const VALUE *restrict y = b->iseq_deoptimized;

    memcpy((void *)x, y, s);
    ISEQ_RESET_ORIGINAL_ISEQ(i);
}

void
iseq_prepare_to_deoptimize(const rb_iseq_t *i)
{
    /* Surprisingly, this function is branch-free (except call to malloc()).
     * Look at assembler output to check this fact. */

    struct list_head *restrict h = &GET_VM()->optimized_iseqs;
    target_t *restrict d         = list_alloc(i);

    iseq_evacuate(i);
    list_add(h, &d->node);
}

void
rb_vm_deoptimize(void)
{
    const struct list_head *h = &GET_VM()->optimized_iseqs;
    target_t *i;
    target_t *n;

    list_for_each_safe (h, i, n, node) {
        iseq_deoptimize(i->iseq);
        ruby_xfree(i);
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
