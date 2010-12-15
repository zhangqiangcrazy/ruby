#include "intervm.h"
#include <stddef.h>
#include <assert.h>
#include <ruby/ruby.h>
#include <ruby/st.h>
#include "gc.h"
#include "node.h"
#include "vm_core.h"
#include "eval_intern.h"

/* As GCs run on every VM, a  GC needs its own VM context.  So inter-VM objects
 * cannot be  GCed (at least on this  impl).  But that doesn't  mean they can't
 * have their object space. */

static const size_t sizeof_an_universe = 0x4000; /* 16KiB */

#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__CYGWIN__) || defined(__GNUC__)
#pragma pack(push, 1)
#endif

struct multiveerse {
    struct universe {
        struct planet {
            struct RObject value;
            VALUE reserved;
            rb_atomic_t refs;
            struct planet *next;
        } *planets;
        struct universe *next;
    } *universes;
    struct planet *the_free;
    rb_atomic_t beat;
    rb_thread_lock_t *the_lock;
} the_world = { 0, 0, 0, 0 };

#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__CYGWIN__) || defined(__GNUC__)
#pragma pack(pop)
#endif

static void mother_of_the_universe(void);
static int is_a_planet(const void *p);
static VALUE intervm_mkproc(VALUE);
static VALUE intervm_str_finalizer(VALUE, VALUE);
static struct planet *consume(void);
static void recycle(struct planet *);

void
Init_intervm(void)
{
    the_world.the_lock = malloc(sizeof *the_world.the_lock);
    ruby_native_thread_lock_initialize(the_world.the_lock);
    mother_of_the_universe();
}

void
InitVM_intervm(void)
{
}

#define cas_p(x, y, z)                          \
    (rb_atomic_cas((rb_atomic_t *)&(x),          \
                   (rb_atomic_t)(y),            \
                   (rb_atomic_t)(z))            \
     == (rb_atomic_t)(y))

void
mother_of_the_universe(void)
{
    long i;
    const unsigned long number_of_planets = sizeof_an_universe / sizeof(struct planet);
    struct planet *planets = malloc(sizeof_an_universe);
    struct universe *newuniv = malloc(sizeof(struct universe));
    struct planet *last = &planets[number_of_planets - 1];
    memset(planets, '\0', sizeof_an_universe);
    for (i=1; i<number_of_planets; i++) {
        planets[i].next = &planets[i - 1];
    }
    newuniv->planets = planets;
    for (;;) {
        struct universe *now = the_world.universes;
        newuniv->next = now;
        if (cas_p(the_world.universes, now, newuniv)) {
            break;
        }
    }
    /* <- this point is suspicious... */
    for (;;) {
        struct planet *now = the_world.the_free;
        planets[0].next = now;
        if (cas_p(the_world.the_free, now, last)) {
            return;
        }
    }
}

int
is_a_planet(const void *p)
{
    /* this is roughly a fake rb_objspace_is_pointer_to_heap */
    /* note: existance of  this function prevents universes to  be reordered or
     * deallocated at all.  a simple loop (without a giant lock) should be able
     * to check all existing live objects without any exceptions.  */
    const char *q = p;
    struct universe *u;
    for (u = the_world.universes; u; u = u->next) {
        char *r = (char*)u->planets;
        if ((r < q) && (q < r + sizeof_an_universe)) {
            return TRUE;
        }
    }
    return FALSE;
}

struct planet *
consume(void)
{
    struct planet *now;
    while ((now = the_world.the_free) != 0) {
        if (cas_p(the_world.the_free, now, now->next)) {
            assert(now->refs == 0);
            now->next = 0;
            return now;
        }
    }
    /* no free planets */
    mother_of_the_universe();
    return consume();
}

void
recycle(planet)
    struct planet *planet;
{
    assert(planet->refs == 0);
    for (;;) {
        struct planet *now = the_world.the_free;
        planet->next = now;
        if (cas_p(the_world.the_free, now, planet)) {
            return;
        }
    }
}

VALUE
rb_intervm_str(str)
    VALUE str;
{
    VALUE ret, proc;
    VALUE str2 = rb_check_string_type(str);
    struct RString *strp = RSTRING(str2);
    struct planet *ours = (void *)strp->as.heap.aux.shared;
    if (FL_TEST(str2, ELTS_SHARED) && is_a_planet(ours)) {
        /* already */
    }
    else {
        /* create one */
        VALUE str3 = rb_str_new_shared(str2);
        rb_str_modify(str3);    /* <- this makes a deep copy */
        ours = consume();
        memmove(&ours->value, (void *)str3, sizeof(struct RString));
        if (FL_TEST(str3, RSTRING_NOEMBED)) {
            /* need to avoid double free */
            RSTRING(str3)->as.heap.ptr = 0;
            RSTRING(str3)->as.heap.len = 0;
            /* save where the pointer was from */
            ours->reserved = (VALUE)(GET_VM()->objspace);
        }
        OBJ_FREEZE(&ours->value);
    }
    /* at this point ours points to a valid live intervm object. */
    ret = rb_str_new_shared((VALUE)&ours->value);
    OBJ_FREEZE(ret);
    return ret;
}

void
rb_intervm_str_descend(self)
    VALUE self;
{
    /* reference count decrement && destruct if this was the last use */
    struct RString *str = RSTRING(self);
    struct planet *ptr = (void *)str->as.heap.aux.shared;
    if (is_a_planet(ptr)) {
        if (rb_atomic_dec(&ptr->refs) == 1) {
            struct RString *str2 = RSTRING(&ptr->value);
            if (FL_TEST(str2, RSTRING_NOEMBED)) {
                struct rb_objspace *space = (void *)ptr->reserved;
                rb_objspace_xfree(space, RSTRING_PTR(str2));
            }
        }
        /* cut the connection anyway to avoid called twice */
        str->as.heap.aux.shared = 0;
    }
}

void
rb_intervm_str_ascend(self)
    VALUE self;
{
    /* ascend is easy; just count up. */
    struct RString *str = RSTRING(self);
    struct planet *ptr = (void *)str->as.heap.aux.shared;
    if (is_a_planet(ptr)) {
        rb_atomic_inc(&ptr->refs);
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
