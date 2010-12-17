#include "intervm.h"
#include <stddef.h>
#include <assert.h>
#include <ruby/ruby.h>
#include <ruby/st.h>
#include <ruby/encoding.h>
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

struct multiveerse {              /**< set of universes */
    struct universe {             /**< set of planets */
        struct planet {           /**< an inter-vm spaceship */
            union {               /**< several possibilities are there: */
                struct RString string;     /**< inter-VM string */
                struct RTypedData data;    /**< typed data (e.g. wormholes) */
                struct darkmatter {        /**< or a new kind of Ruby object */
                    struct RBasic basic;   /**< flags, klass */
                    VALUE value;           /**< the data in question */
                    struct planet *prev;   /**< previous element if any */
                    struct planet *next;   /**< next element if any */
                } darkmatter;
            } as;
            VALUE reserved;       /**< reseved */
            rb_atomic_t refs;     /**< reference counts */
            struct planet *next;  /**< next one */
        } *planets;               /**< the planets in this universe */
        struct universe *next;    /**< next one */
    } *universes;                 /**< the universes in this multiverse */
    struct planet *the_free;      /**< list of free planets */
} the_world = { 0, 0, };

#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__CYGWIN__) || defined(__GNUC__)
#pragma pack(pop)
#endif

static int vmkey_wormhole = 0;

/* @_ko1 said that he has  a lock-free queue implementation so @shyouhei leaves
 * him to make this data structure lock free. */
struct wormhole {
    rb_thread_lock_t lock;        /**< mutex */
    rb_thread_cond_t cond;        /**< condition variable */
    st_table *relations;          /**< owner VMs */
    struct planet *intervm;       /**< intervm identity */
    struct rb_objspace *objspace; /**< where was this struct was allocated */
    struct planet *head;          /**< queue head */
    struct planet *tail;          /**< queue tail */
};

static void Final_intervm(void);
static void mother_of_the_universe(void);
static int is_a_planet(const void *p);
static VALUE intervm_mkproc(VALUE);
static VALUE intervm_str_finalizer(VALUE, VALUE);
static void intervm_str_dealloc(struct planet *);
static inline struct planet *consume(void);
static inline void recycle(struct planet *);
static inline int wormholep(struct planet *);
static void wormhole_mark(void *);
static void wormhole_free(void *);
static size_t wormhole_memsize(const void *);
static VALUE wormhole_alloc(VALUE);
static void wormhole_initial_fill(VALUE);
static void wormhole_dealloc(struct wormhole *);
static void wormhole_ascend(struct wormhole *self, const rb_vm_t *vm);
static void wormhole_descend(struct wormhole *self, const rb_vm_t *vm);
static VALUE wormhole_initialize(VALUE);
static VALUE wormhole_init_copy(VALUE, VALUE);
static void wormhole_push(struct wormhole *, VALUE);
static VALUE wormhole_shift(struct wormhole *);

void
Init_intervm(void)
{
    mother_of_the_universe();
    ruby_at_exit(Final_intervm);
}

void
InitVM_intervm(void)
{
}

int
wormholep(ptr)
    struct planet *ptr;
{
    struct RTypedData *value = &ptr->as.data;
    return
        BUILTIN_TYPE(value) == T_DATA &&
        RTYPEDDATA_P(value) &&
        RTYPEDDATA(value)->type->dmark == wormhole_mark;
}

void
Final_intervm(void)
{
    /* this is roughly a fake rb_objspace_free */
    const unsigned long number_of_planets = sizeof_an_universe / sizeof(struct planet);
    struct universe *p, *q;
    for (p = q = the_world.universes; p; p = q) {
        int i;
        q = p->next;
        for (i = 0; i < number_of_planets; i++) {
            struct planet *r = &p->planets[i];
            if (r->as.data.basic.flags) {
                switch (BUILTIN_TYPE(&r->as)) {
                case T_STRING:
                    /* the   RSTRING(r)->as.heap.ptr  was  allocated   under  a
                     * certain  objspace.   The problem  is,  that objspace  is
                     * already deallocated at the timing of this line.  */
                    r->refs = 0;
                    intervm_str_dealloc(r);
                    break;
                case T_DATA:
                    if (wormholep(r)) {
                        wormhole_dealloc(RTYPEDDATA_DATA(&r->as.data));
                    }
                    else {
                        rb_bug("what's this? needs inspection.");
                    }
                    break;
                case T_ARRAY:
                    if (FL_TEST(&r->as.darkmatter, RARRAY_EMBED_FLAG)) {
                        /* wormhole_elements */
                        break;
                    }
                    /* FALLTHROUGH */
                default:
                    rb_bug("Final_intervm(): unknown data type 0x%x(%p)",
                           BUILTIN_TYPE(&r->as), r);
                    /* NOTREACHED */
                }
            }
        }
    }
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
    struct planet *planets;
    struct universe *newuniv;
    struct planet *last;
    planets = malloc(sizeof_an_universe);
    if (!planets) rb_memerror();
    newuniv = malloc(sizeof(struct universe));
    if (!newuniv) rb_memerror();
    last = &planets[number_of_planets - 1];
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
    memset(planet, '\0', sizeof *planet);
    for (;;) {
        struct planet *now = the_world.the_free;
        planet->next = now;
        if (cas_p(the_world.the_free, now, planet)) {
            return;
        }
    }
}

/*
 * Strings
 */

VALUE
rb_intervm_str(str)
    VALUE str;
{
    VALUE ret;
    struct planet *ours;
    VALUE str2 = rb_check_string_type(str);
    if (is_a_planet((void *)str2)) {
        /* case 1: str itself is already intervm */
        ours = (void *)str2;
    }
    else if (FL_TEST(str2, ELTS_SHARED) &&
             is_a_planet((ours = (void *)RSTRING(str2)->as.heap.aux.shared))) {
        /* case 2: str is a shared, shares intervm */
    }
    else {
        /* case 3: create one */
        VALUE str3 = rb_str_new_shared(str2);
        rb_str_modify(str3);    /* <- this makes a deep copy */
        ours = consume();
        memmove(&ours->as.string, (void *)str3, sizeof(struct RString));
        rb_enc_set_index((VALUE)&ours->as.string, ENCODING_GET(str3));
        ours->as.string.basic.klass = 0;
        if (FL_TEST(str3, RSTRING_NOEMBED)) {
            /* need to avoid double free */
            RSTRING(str3)->as.heap.ptr = 0;
            RSTRING(str3)->as.heap.len = 0;
            /* save where the pointer was from */
            ours->reserved = (VALUE)(GET_VM()->objspace);
        }
        OBJ_FREEZE(&ours->as.string);
    }
    /* at this point ours points to a valid live intervm object. */
    return (VALUE)&ours->as.string;
}

void
intervm_str_dealloc(p)
    struct planet *p;
{
    struct RString *tmp = &p->as.string;
    assert(BUILTIN_TYPE(tmp) == T_STRING);
    if (p->reserved) {
        rb_objspace_xfree((void *)p->reserved, RSTRING(tmp)->as.heap.ptr);
    }
    else if (FL_TEST(tmp, RSTRING_NOEMBED)) {
        free(RSTRING(tmp)->as.heap.ptr);
    }
    recycle(p);
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
            intervm_str_dealloc(ptr);
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
 * Wormholes
 */

void
Init_Wormhole(void)
{
    vmkey_wormhole = rb_vm_key_create();
}

void
InitVM_Wormhole(void)
{
    VALUE klass = rb_define_class_under(rb_cRubyVM, "Wormhole", rb_cData);
    rb_define_alloc_func(klass, wormhole_alloc);
    rb_define_method(klass, "initialize", wormhole_initialize, 0);
    rb_define_method(klass, "initialize_copy", wormhole_init_copy, 0);
    rb_define_method(klass, "send", rb_intervm_wormhole_send, 1);
    rb_define_method(klass, "recv", rb_intervm_wormhole_recv, 0);
    *(VALUE *)ruby_vm_specific_ptr(vmkey_wormhole) = klass;
    #define rb_cWormhole (*(VALUE *)ruby_vm_specific_ptr(vmkey_wormhole))
}

void
wormhole_initial_fill(t)
    VALUE t;
{
    static const rb_data_type_t wormhole_type = {
        "RubyVM::Wormhole", wormhole_mark, wormhole_free, wormhole_memsize,
    };
    static const struct RTypedData template = {
        { T_DATA, Qundef, }, &wormhole_type, 1, 0,
    };
    memmove((void *)t, &template, sizeof template);
}

VALUE
wormhole_alloc(klass)
    VALUE klass;
{
    /* A wormhole can  be duped (no way to restrict  it), so initialize_copy is
     * defined.  This function only allocates the least necessary things. */
    VALUE ret = rb_newobj();
    wormhole_initial_fill(ret);
    RTYPEDDATA(ret)->basic.klass = klass;
    return ret;
}

VALUE
wormhole_initialize(self)
    VALUE self;
{
    /* A wormhole  object, visible from  Ruby level, is  actually a set  of two
     * objects; one  for the VM, one for  inter-VM.  They both point  to a same
     * data pointer:
     *
     *     VM1     inter-VM     VM2
     *   +-----+              +-----+
     *   | obj |----+     +---| obj |
     *   +-----+    |     |   +-----+
     *             +-------+
     *             | share |
     *             +-------+
     */
    if (RTYPEDDATA_DATA(self)) {
        rb_raise(rb_eArgError, "already.");
    }
    else {
        struct planet *pla = consume();
        struct wormhole *wormhole = xmalloc(sizeof(struct wormhole));
        wormhole_initial_fill((VALUE)&pla->as.data);

        ruby_native_thread_lock_initialize(&wormhole->lock);
        ruby_native_cond_initialize(&wormhole->cond);
        wormhole->relations = st_init_numtable();
        wormhole->intervm = pla;
        wormhole->objspace = GET_VM()->objspace;
        wormhole->head = 0;
        wormhole->tail = 0;

        wormhole_ascend(wormhole, GET_VM());
        RTYPEDDATA_DATA(self) = RTYPEDDATA_DATA(&pla->as.data) = wormhole;

        return self;
    }
}

VALUE
wormhole_init_copy(dest, src)
    VALUE dest, src;
{
    if (RTYPEDDATA_DATA(dest)) {
        rb_raise(rb_eArgError, "already.");
    }
    else if (!RTYPEDDATA_DATA(src)) {
        /* no copy needed */
        return dest;
    }
    else {
        VALUE dest2 = rb_obj_init_copy(dest, src);
        struct wormhole *ptr = RTYPEDDATA_DATA(src);
        wormhole_ascend(ptr, GET_VM());
        RTYPEDDATA_DATA(dest2) = ptr;
        return dest2;
    }
}

VALUE
rb_intervm_wormhole_new(void)
{
    return wormhole_initialize(wormhole_alloc(rb_cWormhole));
}

void
wormhole_dealloc(self)
    struct wormhole *self;
{
    /* this funcsion assumens a lock on entrance */
    struct rb_objspace *objspace = self->objspace;
    struct planet *p, *q;
    for (p = q = self->head; p; p = q) {
        VALUE tmp = p->as.darkmatter.value;
        q = p->next;
        if (RBASIC(tmp)->flags) {
            switch (BUILTIN_TYPE(tmp)) {
            case T_DATA:
                if (wormholep((void *)tmp)) {
                    /* wormholes cannot be  recursively deallocated since there
                     * might be other references remaining to it. */
                    wormhole_descend(RTYPEDDATA_DATA(tmp), (void *)self);
                }
                break;
            case T_STRING:
                rb_intervm_str_descend((void *)tmp);
                break;
            }
        }
        recycle(p);
    }
    recycle(self->intervm);
    st_free_table(self->relations);   /* this hash has no extra memory to free */
    ruby_native_cond_destroy(&self->cond);
    ruby_native_thread_unlock(&self->lock);
    ruby_native_thread_lock_destroy(&self->lock);
    rb_objspace_xfree(objspace, self);
}

void
wormhole_ascend(self, vm)
    struct wormhole *self;
    const rb_vm_t *vm;
{
    ruby_native_thread_lock(&self->lock);
    {
        st_data_t val = 0;
        st_lookup(self->relations, (st_data_t)vm, &val);
        st_insert(self->relations, (st_data_t)vm, ++val);
    }
    ruby_native_thread_unlock(&self->lock);
}

void
wormhole_descend(self, vm)
    struct wormhole *self;
    const rb_vm_t *vm;
{
    ruby_native_thread_lock(&self->lock);
    {
        st_data_t val = 0;
        if (st_delete(self->relations, (st_data_t *)&vm, &val)) {
            if (--val > 0) {
                st_insert(self->relations, (st_data_t)vm, val);
            }
            else if (self->relations->num_entries == 0) {
                /* orphan, delete */
                wormhole_dealloc(self);
                return;         /* OK not to unlock; destructed already */
            }
        }
    }
    ruby_native_thread_unlock(&self->lock);
}

void
wormhole_mark(ptr)
    void *ptr;
{
    /* nothing to mark? really? */
}

void
wormhole_free(ptr)
    void *ptr;
{
    wormhole_descend(ptr, GET_VM());
}

size_t
wormhole_memsize(ptr)
    const void *ptr;
{
    /* I'm not sure for the exact spec of what should it return ... */
    const struct planet *p = ptr;
    struct wormhole *w = RTYPEDDATA_DATA(&p->as.data);
    if (w->objspace == GET_VM()->objspace) {
        return sizeof(struct wormhole);
    }
    else {
        return 0;
    }
}

void
wormhole_push(hole, obj)
    struct wormhole *hole;
    VALUE obj;
{
    static const struct darkmatter template = {
        { T_ARRAY | RARRAY_EMBED_FLAG | (3 << RARRAY_EMBED_LEN_SHIFT), 0, },
    };
    struct planet *p = consume();
    struct darkmatter *d = &p->as.darkmatter;
    memmove(d, &template, sizeof template);
    ruby_native_thread_lock(&hole->lock);

    d->value = obj;
    d->prev = hole->head;
    if (hole->head) hole->head->as.darkmatter.prev = p;
    if (!hole->tail) hole->tail = p;
    hole->head = p;

    ruby_native_cond_signal(&hole->cond);
    ruby_native_thread_unlock(&hole->lock);
}

VALUE
wormhole_shift(hole)
    struct wormhole *hole;
{
    VALUE ret;
    struct planet *dm;
    ruby_native_thread_lock(&hole->lock);
    while (!hole->tail) {
        ruby_native_cond_wait(&hole->cond, &hole->lock);
    }

    dm = hole->tail;
    hole->tail = dm->as.darkmatter.prev;
    if (!hole->tail) hole->head = 0;

    ruby_native_thread_unlock(&hole->lock);

    ret = dm->as.darkmatter.value;
    recycle(dm);
    return ret;
}

VALUE
rb_intervm_wormhole_send(self, obj)
    VALUE self, obj;
{
    /* Current limitation is that we can only usr strings or wormholes. */
    struct wormhole *ptr = RTYPEDDATA_DATA(self);
    if (rb_obj_class(obj) == rb_cWormhole) {
        struct wormhole *ptr2 = RTYPEDDATA_DATA(obj);
        if (ptr == ptr2) {
            rb_raise(rb_eArgError, "infinite recursion detected");
        }
        else {
            wormhole_ascend(ptr2, (void *)ptr);
            wormhole_push(ptr, (VALUE)&ptr2->intervm->as.data);
        }
    }
    else {
        VALUE str = rb_check_string_type(obj);
        VALUE str2 = rb_intervm_str(str);
        rb_intervm_str_ascend(str2); /* prevent deallocation */
        wormhole_push(ptr, str2);
    }
    return obj;
}

VALUE
rb_intervm_wormhole_recv(self)
    VALUE self;
{
    struct wormhole *ptr = RTYPEDDATA_DATA(self);
    VALUE intervm = wormhole_shift(ptr);
    switch (BUILTIN_TYPE(intervm)) {
        VALUE ret;
    case T_STRING:
        rb_intervm_str_descend(intervm);
        ret = rb_str_new_shared(intervm);
        RSTRING(ret)->basic.klass = rb_cString;
        return ret;
    case T_DATA:
        wormhole_descend(RTYPEDDATA_DATA(intervm), (void *)ptr);
        ret = wormhole_alloc(rb_cWormhole);
        return wormhole_init_copy(ret, intervm);
    default:
        rb_bug("rb_intervm_wormhole_recv(): unknown data type 0x%x(%p)",
               BUILTIN_TYPE(intervm), (void *)intervm);
        /* NOTREACHED */
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
 * c-file-style: "ruby"
 * c-doc-comment-style: javadoc
 * End:
 */
