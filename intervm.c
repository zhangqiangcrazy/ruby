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
                struct RArray array;       /**< inter-VM array */
                struct RFloat real;        /**< inter-VM float */
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
            size_t bytes;         /**< size of this planet */
            struct planet *next;  /**< next one */
        } *planets;               /**< the planets in this universe */
        struct universe *next;    /**< next one */
    } *universes;                 /**< the universes in this multiverse */
    struct planet *the_free;      /**< list of free planets */
} the_world = { 0, 0, };

#if defined(_MSC_VER) || defined(__BORLANDC__) || defined(__CYGWIN__) || defined(__GNUC__)
#pragma pack(pop)
#endif

#define PLANET(x) ((struct planet*)(x))

static int vmkey_channel = 0;

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
    size_t bytes[2];              /**< tx, rx */
};

static struct vm_manager {
    rb_thread_lock_t lock;      /**< mutex */
    st_table *machines;         /**< set of VMs */
    rb_vm_t *main;              /**< main VM */
} vm_manager;

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
static struct planet *wormhole_shift(struct wormhole *);
enum judge { unacceptable, duplicatable, valid };
static enum judge wormhole_sendaable_p(VALUE obj);
static VALUE wormhole_convert_this_obj(VALUE, const struct wormhole *wh);
static VALUE wormhole_interpret_this_obj(VALUE, const void *);
static VALUE rb_intervm_wormhole_get_bytes(VALUE);
static VALUE rb_intervm_wormhole_reset_bytes(VALUE);
static int vm_foreach_i(st_data_t, st_data_t, st_data_t);
/* extern */ void ruby_vmmgr_add(rb_vm_t *vm);

void
Init_intervm(void)
{
    vm_manager.machines = st_init_numtable();
    vm_manager.main = 0;
    ruby_native_thread_lock_initialize(&vm_manager.lock);
    mother_of_the_universe();   /* not required, but makes things faster */
    ruby_at_exit(Final_intervm);

    /*
     * This is  delayed til  this point  because the main  VM had  already been
     * created long before the VM manager boots up.
     */
    ruby_vmmgr_add(GET_VM());
    vm_manager.main = GET_VM();
    rb_atomic_inc(&GET_VM()->references); /* The main VM can never be freed! */
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
                case T_FLOAT:
                    break;      /* needs nothing */
                case T_ARRAY:
                    break;
                default:
                    rb_bug("Final_intervm(): unknown data type 0x%x(%p)",
                           BUILTIN_TYPE(&r->as), r);
                    /* NOTREACHED */
                }
            }
        }
    }

    /* VMs should have been freed at this point.  This table must be emoty */
    st_free_table(vm_manager.machines);
    ruby_native_thread_lock_destroy(&vm_manager.lock);
}

#define cas_p(x, y, z)                          \
    (rb_atomic_cas((rb_atomic_t *)&(x),         \
                   (rb_atomic_t)(y),            \
                   (rb_atomic_t)(z))            \
     == (rb_atomic_t)(y))

void
mother_of_the_universe(void)
{
    static rb_atomic_t flag = 0;
    long i;
    const unsigned long number_of_planets = sizeof_an_universe / sizeof(struct planet);
    struct planet *planets;
    struct universe *newuniv;
    struct planet *last;
    if (!cas_p(flag, 0, 1)) {
        return;
    }
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
            while (!cas_p(flag, 1, 0))
                ;
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
            now->bytes = 0;
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
    if (planet->as.darkmatter.value != Qnil) {
        fprintf(stderr, "%d ", planet->as.darkmatter.value);
    }
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
    VALUE str2 = rb_check_string_type(str);
    if (FL_TEST(str2, ELTS_SHARED) && FL_TEST(str2, RSTRING_NOEMBED)) {
        /* recur */
        return rb_intervm_str(RSTRING(str2)->as.heap.aux.shared);
    }
    else if (is_a_planet((void *)str2)) {
        /* already */
        return str2;
    }
    else {
        struct planet *ours = consume();
        VALUE ret = (VALUE)&ours->as.string;
        memcpy((void*)ret, (void*)str2, sizeof(struct RString));
        ours->bytes = sizeof(struct RString);
        if (FL_TEST(str2, RSTRING_NOEMBED)) {
            RSTRING(str2)->as.heap.aux.shared = ret;
            FL_SET(str2, ELTS_SHARED);
            ours->reserved = (VALUE)GET_VM()->objspace; /* save where was it from */
        }
        ours->as.string.basic.klass = 0;
        OBJ_FREEZE(ret);
        return ret;
    }
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
    vmkey_channel = rb_vm_key_create();
}

void
InitVM_Wormhole(void)
{
    VALUE klass = rb_define_class_under(rb_cRubyVM, "Channel", rb_cData);
    rb_define_alloc_func(klass, wormhole_alloc);
    rb_define_method(klass, "initialize", wormhole_initialize, 0);
    rb_define_method(klass, "initialize_copy", wormhole_init_copy, 0);
    rb_define_method(klass, "send", rb_intervm_wormhole_send, 1);
    rb_define_method(klass, "recv", rb_intervm_wormhole_recv, 0);
    rb_define_method(klass, "bytes", rb_intervm_wormhole_get_bytes, 0);
    rb_define_method(klass, "clear_bytes", rb_intervm_wormhole_reset_bytes, 0);
    *(VALUE *)ruby_vm_specific_ptr(vmkey_channel) = klass;
    #define rb_cChannel (*(VALUE *)ruby_vm_specific_ptr(vmkey_channel))
}

void
wormhole_initial_fill(t)
    VALUE t;
{
    static const rb_data_type_t wormhole_type = {
        "RubyVM::Channel", wormhole_mark, wormhole_free, wormhole_memsize,
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

/*
 *  call-seq:
 *     RubyVM::Channel.new -> a channel
 *
 *  A channel is much  like a queue -- as long as that  do not travel outside a
 *  VM.   Once  explicitly  shared  among   VMs,  it  can  act  as  a  inter-VM
 *  communication courier.
 *
 *     c = RubyVM::Channel.new
 *     v = RubyVM.new(...)
 *     v.start c # shares c among this VM and v
 *     v.send "foobarbaz" # or something.
 *
 *  A real-world example is lib/drb/mvm.rb
 */
VALUE
wormhole_initialize(self)
    VALUE self;
{
    /* A RubyVM::Channel object, visible from  Ruby level, is actually a set of
     * two Wormhole objects; one for the VM, one for inter-VM.  They both point
     * to a same data pointer:
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
        wormhole->bytes[0] = 0;
        wormhole->bytes[1] = 0;

        wormhole_ascend(wormhole, GET_VM());
        RTYPEDDATA_DATA(self) = RTYPEDDATA_DATA(&pla->as.data) = wormhole;

        return self;
    }
}

/*
 * call-seq:
 *    ch.dup -> a new channel
 *
 * Duplicates a channel -- much like IO#dup.  Reads/writes are not independent.
 */
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
        /* src  object might not  have its  klass because  it might  be sourced
         * from outer-space.   rb_obj_init_copy() implies a klass  so we cannot
         * use it. */
        struct wormhole *ptr = RTYPEDDATA_DATA(src);
        rb_check_frozen(dest);
        wormhole_ascend(ptr, GET_VM());
        RTYPEDDATA_DATA(dest) = ptr;
        return dest;
    }
}

VALUE
rb_intervm_wormhole_new(void)
{
    return wormhole_initialize(wormhole_alloc(rb_cChannel));
}

void
wormhole_dealloc(self)
    struct wormhole *self;
{
    /* this funcsion assumens a lock on entrance */
    struct rb_objspace *objspace = self->objspace;
    struct planet *p, *q;
    for (p = q = self->tail; p; p = q) {
        VALUE tmp = p->as.darkmatter.value;
        q = p->next;
        switch (TYPE(tmp)) {
        case T_DATA:
            if (wormholep((void *)tmp)) {
                /* wormholes  cannot  be  recursively deallocated  since  there
                 * might be other references remaining to it. */
                wormhole_descend(RTYPEDDATA_DATA(tmp), (void *)self);
            }
            break;
        case T_STRING:
            rb_intervm_str_descend(tmp);
            break;
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

#define PLANET_BYTES(pla) \
    IMMEDIATE_P(pla) ? 0 : \
    pla == Qtrue     ? 0 : \
    pla == Qfalse    ? 0 : \
    pla == Qnil      ? 0 : \
    pla == Qundef    ? 0 : \
    PLANET(pla)->bytes;


void
wormhole_push(hole, obj)
    struct wormhole *hole;
    VALUE obj;
{
    static const struct darkmatter template = {
        { T_ARRAY | RARRAY_EMBED_FLAG | (3 << RARRAY_EMBED_LEN_SHIFT), 0, },
        Qundef, 0, 0
    };
    struct planet *p = consume();
    struct darkmatter *d = &p->as.darkmatter;
    size_t bytes = PLANET_BYTES(obj);
    PLANET(d)->bytes = bytes;   /* to ease shift() */

    memmove(d, &template, sizeof template);
    ruby_native_thread_lock(&hole->lock);

    /* if (hole->bytes[0] + bytes < hole->bytes[0]) { */
    /*     rb_raise(rb_eArgError, "integer overflow"); */
    /* } */
    hole->bytes[0] += bytes;

    d->value = obj;
    d->prev = hole->head;
    if (hole->head) hole->head->as.darkmatter.next = p;
    if (!hole->tail) hole->tail = p;
    hole->head = p;

    ruby_native_cond_signal(&hole->cond);
    ruby_native_thread_unlock(&hole->lock);
}

struct planet *
wormhole_shift(hole)
    struct wormhole *hole;
{
    VALUE ret;
    struct planet *dm;
    size_t bytes;

    ruby_native_thread_lock(&hole->lock);
    while (!hole->tail) {
        ruby_native_cond_wait(&hole->cond, &hole->lock);
    }

    dm = hole->tail;
    hole->tail = dm->as.darkmatter.next;
    if (!hole->tail) hole->head = 0;

    bytes = dm->bytes;
    /* if (hole->bytes[1] + bytes < hole->bytes[1]) { */
    /*     rb_raise(rb_eArgError, "integer overflow"); */
    /* } */
    hole->bytes[1] += bytes;

    ruby_native_thread_unlock(&hole->lock);

    return dm;
}

static enum judge
wormhole_sendable_p(obj)
    VALUE obj;
{
    VALUE tmp;
    if (rb_generic_ivar_table(obj)) {
        return unacceptable;
    }
    switch(TYPE(obj)) {
        int i;
    case T_FIXNUM:
    case T_SYMBOL:
    case T_TRUE:
    case T_FALSE:
    case T_NIL:
    case T_UNDEF:
    case T_FLOAT:
        return valid;
    case T_STRING:
        /* all strings visible from Ruby levels are _not_ intervm. */
        return duplicatable;
    case T_ARRAY:
        /* arrays are duplicatable if all its contents are not invalid */
        for (i=0; i<RARRAY_LEN(obj); i++) {
            if (wormhole_sendable_p(RARRAY_PTR(obj)[i]) ==unacceptable) {
                return unacceptable;
            }
        }
        return duplicatable;
    case T_DATA:
        /* channels are valid, otherd aren't. */
        if (RTYPEDDATA_P(obj) && RTYPEDDATA_TYPE(obj)->dmark == wormhole_mark) {
            return valid;
        }
        else {
            return unacceptable;
        }
    default:
        return unacceptable;
    }
}

VALUE
wormhole_convert_this_obj(obj, wh)
    VALUE obj;
    const struct wormhole *wh;
{
    switch(TYPE(obj)) {
        int i, j;
        VALUE ret;
        struct wormhole *wh2;
        size_t bytes;
    case T_STRING:
        ret = rb_intervm_str(obj);
        rb_intervm_str_ascend(ret); /* prevent deallocation */
        return ret;
    case T_DATA:
        wh2 = RTYPEDDATA_DATA(obj);
        wormhole_ascend(wh2, (void *)wh);
        return (VALUE)&wh2->intervm->as.data;
    case T_ARRAY:
        /* intervm arrays are not shared; they are always duplicated */
        j = RARRAY_LEN(obj);
        ret = (VALUE)&consume()->as.array;
        memcpy((void *)ret, (void *)obj, sizeof(struct RArray));
        bytes = sizeof(struct RArray);
        RBASIC(ret)->klass = 0;
        if (!FL_TEST(ret, RARRAY_EMBED_FLAG)) {
            FL_UNSET(ret, ELTS_SHARED); /* not used though */
            RARRAY(ret)->as.heap.ptr = malloc(sizeof(VALUE) * j);
            bytes += sizeof(VALUE) * j;
        }
        for (i=0; i<j; i++) {
            VALUE v = wormhole_convert_this_obj(RARRAY_PTR(obj)[i], wh);
            RARRAY_PTR(ret)[i] = v;
            bytes += PLANET_BYTES(v);
        }
        PLANET(ret)->bytes = bytes;
        return ret;
    case T_FLOAT:
        ret = (VALUE)&consume()->as.real;
        memcpy((void *)ret, (void *)obj, sizeof(struct RFloat));
        PLANET(ret)->bytes = sizeof(struct RFloat);
        RBASIC(ret)->klass = 0;
        return ret;
    default:
        return obj;
    }
}

/*
 * call-seq:
 *    ch.send(msg)
 *
 * A sent message can be recieved using ch.recv
 */
VALUE
rb_intervm_wormhole_send(self, obj)
    VALUE self, obj;
{
    VALUE str = rb_check_string_type(obj);
    struct wormhole *ptr = RTYPEDDATA_DATA(self);
    if (!NIL_P(str)) {
        obj = str;
    }
    switch (wormhole_sendable_p(obj)) {
        VALUE tmp;
    case unacceptable:
        if (0) {
            rb_raise(rb_eTypeError, "type mismatch (%s), String expected",
                     rb_obj_classname(obj));
        }
        else {
            tmp = rb_intervm_str(rb_marshal_dump(obj, Qnil));
            rb_intervm_str_ascend(tmp); /* prevent deallocation */
            FL_SET(tmp, FL_MARK); /* hack */
            PLANET(tmp)->bytes += RSTRING_LEN(tmp);
            wormhole_push(ptr, tmp);
            break;
        }
    case valid:
    case duplicatable:
        tmp = wormhole_convert_this_obj(obj, ptr);
        wormhole_push(ptr, tmp);
        break;
    }
    return self;
}

VALUE
rb_intervm_wormhole_send_immediate(self, obj)
    VALUE self, obj;
{
    assert(IMMEDIATE_P(obj));
    wormhole_push(RTYPEDDATA_DATA(self), obj);
    return self;
}

VALUE
wormhole_interpret_this_obj(obj, vm)
    VALUE obj;
    const void *vm;
{
    VALUE ret;
    switch (TYPE(obj)) {
        int i, j;
    case T_NIL:
    case T_FALSE:
    case T_TRUE:
    case T_FIXNUM:
    case T_SYMBOL:
        return obj;
    case T_STRING:
        if(FL_TEST(obj, FL_MARK)) {
            ret = rb_marshal_load(obj);
        }
        else {
            ret = rb_str_new_shared(obj);
            RSTRING(ret)->basic.klass = rb_cString;
        }
        rb_intervm_str_descend(obj);
        return ret;
    case T_DATA:
        ret = wormhole_alloc(rb_cChannel);
        wormhole_init_copy(ret, obj);
        wormhole_descend(RTYPEDDATA_DATA(obj), vm);
        return ret;
    case T_ARRAY:
        j = RARRAY_LEN(obj);
        ret = rb_ary_new2(j);
        for (i=0; i<j; i++) {
            rb_ary_push(ret, wormhole_interpret_this_obj(RARRAY_PTR(obj)[i], vm));
        }
        if (!FL_TEST(obj, RARRAY_EMBED_FLAG)) {
            free(RARRAY_PTR(obj));
        }
        recycle(PLANET(obj));
        return ret;
    case T_FLOAT:
        ret = rb_float_new(RFLOAT_VALUE(obj));
        recycle(PLANET(obj));
        return ret;
    default:
        rb_bug("wormhole_interpret_this_obj(): unknown data type 0x%x(%p)",
               BUILTIN_TYPE(obj), (void *)obj);
        /* NOTREACHED */
    }
}

extern void *rb_thread_call_without_gvl(
    rb_blocking_function_t *func, void *data1,
    rb_unblock_function_t *ubf, void *data2);

/*
 * call-seq:
 *    ch.recv -> msg
 *
 * Blocks when ncessesary.
 */
VALUE
rb_intervm_wormhole_recv(self)
    VALUE self;
{
    struct wormhole *ptr = RTYPEDDATA_DATA(self);
    struct planet *darkmatter = rb_thread_call_without_gvl(
            (rb_blocking_function_t *)wormhole_shift, ptr, RUBY_UBF_IO, 0);
    VALUE ret = wormhole_interpret_this_obj(darkmatter->as.darkmatter.value, ptr);
    recycle(darkmatter);
    return ret;
}

VALUE
rb_intervm_wormhole_peek(self, ifnone)
    VALUE self, ifnone;
{
    struct planet *darkmatter;
    VALUE ret = ifnone;
    if (self != Qundef) {
        struct wormhole *ptr = RTYPEDDATA_DATA(self);
        ruby_native_thread_lock(&ptr->lock);

        darkmatter = ptr->tail;
        if (darkmatter) {
            VALUE tmp = darkmatter->as.darkmatter.value;
            ret = wormhole_interpret_this_obj(tmp, ptr);
            ptr->tail = darkmatter->as.darkmatter.prev;
            if (!ptr->tail) {
                ptr->head = 0;
            }
            recycle(darkmatter);
        }

        ruby_native_thread_unlock(&ptr->lock);
    }
    return ret;
}

int
rb_intervm_wormhole_is_empty(self)
    VALUE self;
{
    /* this  operation does  not  guarantee any  thread  coherency anyway.   No
     * edstructive operations  are issued, so  no lock should just  suffice for
     * the purpose.*/
    struct wormhole *ptr = RTYPEDDATA_DATA(self);
    return !ptr->head;
}

/*
 * call-seq:
 *    ch.bytes -> [tx, rx]
 *
 * Number of transmitted and received octets since the last ch.clear_bytes.
 */
VALUE
rb_intervm_wormhole_get_bytes(self)
    VALUE self;
{
    VALUE ret = Qundef;
    struct wormhole *ptr = RTYPEDDATA_DATA(self);
    ruby_native_thread_lock(&ptr->lock);
    ret = rb_ary_new3(2, SIZET2NUM(ptr->bytes[0]), SIZET2NUM(ptr->bytes[1]));
    ruby_native_thread_unlock(&ptr->lock);
    return ret;
}

/*
 * call-seq:
 *    ch.clear_bytes -> self
 *
 * reset the stat.
 */
VALUE
rb_intervm_wormhole_reset_bytes(self)
    VALUE self;
{
    struct wormhole *ptr = RTYPEDDATA_DATA(self);
    ruby_native_thread_lock(&ptr->lock);
    ptr->bytes[0] = ptr->bytes[1] = 0;
    ruby_native_thread_unlock(&ptr->lock);
    return self;
}

/* 
 * VM management
 */

/* Beware: VM  management related APIs  are declared in  include/ruby/vm.h, not
 * in intervm.h. */

rb_vm_t *
ruby_vm_new(argc, argv)
    int argc;
    char **argv;
{
    rb_vm_t *vm;

    if (!(vm = ruby_init()) &&
        !(vm = ruby_make_bare_vm())) {
        return 0;
    }
    else {
        vm->argc = argc;
        vm->argv = argv;
        ruby_vmmgr_add(vm);
        return vm;
    }
}

int
ruby_vm_destruct(vm)
    rb_vm_t *vm;
{
    st_data_t k, v;
    ruby_vmptr_destruct(vm);
    ruby_native_thread_lock(&vm_manager.lock);

    if (ruby_vm_main_p(vm)) {
        /* main VM shall not be freed */
    }
    else {
        k = (st_data_t)vm;
        st_delete_safe(vm_manager.machines, &k, &v, 0);
        assert(v == 0);
        if (vm_manager.main == vm) {
            vm_manager.main = 0;
        }
        free(vm);
    }

    ruby_native_thread_unlock(&vm_manager.lock);
    return 0;
}

int
ruby_vm_main_p(vm)
    rb_vm_t *vm;
{
    return vm == vm_manager.main;
}

/* temporary use */
struct vm_foreach_data {
    int (*func)(rb_vm_t *, void *);
    void *data;
};

int
vm_foreach_i(key, val, data)
    st_data_t key, val, data;
{
    struct vm_foreach_data *tmp = (void *)data;
    rb_vm_t *vm = (void *)key;
    if (!key) {
        return ST_CONTINUE;
    }
    else if (tmp->func(vm, tmp->data) == 0) {
        return ST_STOP;
    }
    else {
        return ST_CONTINUE;
    }
}

void
ruby_vm_foreach(int (*func)(rb_vm_t *, void *), void *arg)
{
    struct vm_foreach_data tmp;
    tmp.func = func;
    tmp.data = arg;
    st_foreach(vm_manager.machines, vm_foreach_i, (st_data_t)&tmp);
    st_cleanup_safe(vm_manager.machines, 0);
}

void
ruby_vmmgr_add(vm)
    rb_vm_t *vm;
{
    ruby_native_thread_lock(&vm_manager.lock);
    st_insert(vm_manager.machines, (st_data_t)vm, 0);
    if (!vm_manager.main) {
        vm_manager.main = vm;
    }
    ruby_native_thread_unlock(&vm_manager.lock);
}

VALUE
join_internal(ptr)
    void *ptr;
{
    rb_vm_t* vm = ptr;
    ruby_native_cond_wait(&vm->global_vm_waiting, &vm_manager.lock);
    return Qnil;
}

int
ruby_vm_join(vm)
    rb_vm_t *vm;
{
    ruby_native_thread_lock(&vm_manager.lock);
    if (st_lookup(vm_manager.machines, (st_data_t)vm, 0)) {
        while (vm->status != RB_VM_KILLED) {
            rb_thread_call_without_gvl(join_internal, vm, RUBY_UBF_IO, 0);
        }
    }
    ruby_native_thread_unlock(&vm_manager.lock);
    return 1;
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
