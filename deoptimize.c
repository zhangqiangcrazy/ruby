/**
 * ISeq deoptimization infrastructure, implementation.
 *
 * @file      deoptimize.c
 * @author    Urabe, Shyouhei.
 * @date      Apr. 11th, 2016
 * @copyright Ruby's
 */

#include "ruby/config.h"

#include <stddef.h>
#include <stdint.h>
#include "vm_core.h"
#include "iseq.h"
#include "ruby/st.h"
#include "gc.h"
#include "deoptimize.h"

typedef struct iseq_to_deoptimize target_t;
typedef struct rb_iseq_constant_body body_t;

static st_table *optimized_iseqs(void);
static void register_optimized_iseqs(const rb_iseq_t *i);
static int callback(st_data_t *k, st_data_t *v, st_data_t a, int x);
static void iseq_deoptimize(const rb_iseq_t *i);

st_table *
optimized_iseqs(void)
{
    return GET_VM()->optimized_iseqs;
}

const VALUE *
iseq_deoptimized_seq(const rb_iseq_t *i)
{
    return i->body->deoptimize->ptr;
}

void
register_optimized_iseqs(const rb_iseq_t *i)
{
    st_data_t j, k;

    for (j = k = (st_data_t)i; j == Qundef; j = k) {
        st_update(optimized_iseqs(), k, callback, (st_data_t)&j);
    }
}

int
callback(
    st_data_t *keyp,
    st_data_t *valp,
    st_data_t newval,
    int existp)
{
    st_data_t *ptr = (st_data_t *)newval;

    if (! existp) {
        *ptr = *keyp;
        *valp = Qfalse;
        return ST_CONTINUE;
    }
    else if (rb_objspace_garbage_object_p(*keyp)) {
        /* this iseq might already be unmarked, just not swept yet */
        *ptr = Qundef;
        return ST_DELETE;
    }
    else {
        *ptr = *keyp;
        return ST_STOP;
    }
}

void
iseq_prepare_to_deoptimize(const rb_iseq_t *i, rb_serial_t t)
{
    body_t *b = i->body;

    if (b->deoptimize) {
        memcpy((void *)&b->deoptimize->created_at, &t, sizeof(t));
    }
    else {
        const VALUE *x = b->iseq_encoded;
        unsigned int n = b->iseq_size;
        size_t s       = sizeof(VALUE) * n;
        void *y        = ruby_xmalloc(s);
        target_t *d    = ruby_xmalloc(sizeof(*d));
        target_t buf   = { t, y };
        b->deoptimize  = d;
        memcpy(d, &buf, sizeof(buf));
        memcpy(y, x, s);
        register_optimized_iseqs(i);
    }
}

void
iseq_to_deoptimize_free(const target_t *i)
{
    if (UNLIKELY(! i)) {
        return;
    }
    else {
        st_data_t s = (st_data_t)i;
        st_delete(optimized_iseqs(), &s, NULL);
        ruby_xfree((void *)i->ptr);
        ruby_xfree((void *)i);
    }
}

size_t
iseq_to_deoptimize_memsize(const body_t *b)
{
    const target_t *i = b->deoptimize;
    const size_t ret  = sizeof(*i);

    if (UNLIKELY(! i)) {
        return 0;
    }
    else if (LIKELY(i->ptr)) {
        return ret + b->iseq_size * sizeof(i->ptr[0]);
    }
    else {
        return ret;
    }
}

void
iseq_deoptimize(const rb_iseq_t *i)
{
    rb_serial_t const t   = ruby_vm_global_timestamp;
    enum rb_purity p      = rb_purity_is_unpredictable;
    body_t *b             = i->body;
    const target_t *d     = b->deoptimize;
    const uintptr_t *orig = d->ptr;
    unsigned j;

    memcpy((void *)b->iseq_encoded, orig, b->iseq_size * sizeof(VALUE));
    memcpy((void *)&b->purity, &p, sizeof(p));
    memcpy((void *)&d->created_at, &t, sizeof(t));
    ISEQ_RESET_ORIGINAL_ISEQ(i);
    for (j = 0; j < b->ci_size; j++) {
        b->cc_entries[j].temperature = 0;
    }
}

void
rb_purge_stale_iseqs(const rb_vm_t *vm)
{
    st_data_t k;
    st_table *h = vm->optimized_iseqs;

    while (st_shift(h, &k, NULL)) {
        iseq_deoptimize((const rb_iseq_t *)k);
    }
}
