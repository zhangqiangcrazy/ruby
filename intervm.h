#ifndef RUBY_INTER_VM_H_WAS_INCLUDED_P
#define RUBY_INTER_VM_H_WAS_INCLUDED_P
/**
 * @file intervm.h
 * @brief Inter-VM memory management
 * @author Urabe, Shyouhei
 * @date 14th Dec., 2010
 *
 * On a multi-VM environment  there are some kind of info which  are not a part
 * of  any  VMs;  VMs   themselves,  VM  manager,  VM-to-VM  messages,  message
 * manager...   And those  datum  are not  handled  by our  GC  (because GC  is
 * per-VM).  So they need special care.
 */

#include "ruby/ruby.h"

#ifndef __GNUC__
#define __attribute__(x)        /**< GCC hack. */
#endif

/* 
 * Atomic data types
 */

/**
 * @brief atomic operands
 *
 * Some  sort of atomic  operations are  mandatory for  this system  because of
 * MVM's concurrent nature.  Here we define  a set of data and operations to be
 * used for that purpose.
 */
/*
 * rb_atomic_t is  a integral type, unsigned,  same size as  VALUE.  See ruby.h
 * for what possibility are there.
 */
#if defined SIZEOF_UINTPTR_T && SIZEOF_UINTPTR_T == SIZEOF_VALUE
typedef uintptr_t rb_atomic_t;
#elif defined SIZEOF_LONG_LONG && SIZEOF_LONG_LONG == SIZEOF_VALUE
typedf unsigned LONG_LONG rb_atomic_t;
#elif SIZEOF_LONG == SIZEOF_VALUE
typedf unsigned long rb_atomic_t;
#else
#error !?
#endif

/**
 * @brief Interlocked compare-and-swap
 *
 * This is the "lock cmpxchg".   Issues a memory barrier and atomically compare
 * the address content with the latter argument.
 *
 * @param[out]  ptr  an address to compare.
 * @param[in]   old  expected value for *ptr.
 * @param[in]   set  what to write into *ptr.
 * @returns the  previous value of *ptr  when this operation  was called.  Thus
 * you can check if the operations was successful by comparing the return value
 * with old.
 */
static inline rb_atomic_t
rb_atomic_cas(rb_atomic_t *ptr, rb_atomic_t old, rb_atomic_t set)
    __attribute__((__always_inline__))
    __attribute__((__warn_unused_result__))
    __attribute__((__nonnull__))
    __attribute__((__nothrow__));

/**
 * @brief Interlocked increment
 *
 * This is  the "lock inc".  Issues  a memory barrier  and atomically increment
 * the address  content.  Note  however, that a  rb_atomic_t type  is unsigned,
 * i.e. it will round-trip when overflow.
 * @sa rb_atomic_dec()
 *
 * @param[out]  ptr  an address to increment.
 * @returns the previous value of *ptr when this operation was called.
 */
static inline rb_atomic_t rb_atomic_inc(rb_atomic_t *ptr)
    __attribute__((__always_inline__))
    __attribute__((__nonnull__))
    __attribute__((__nothrow__));

/**
 * @brief Interlocked decrement
 *
 * This is  the "lock dec".  Issues  a memory barrier  and atomically decrement
 * the address  content.  Note  however, that a  rb_atomic_t type  is unsigned,
 * i.e. it will round-trip when underflow.
 * @sa rb_atomic_inc()
 *
 * @param[out]  ptr  an address to decrement.
 * @returns the previous value of *ptr when this operation was called.
 */
static inline rb_atomic_t rb_atomic_dec(rb_atomic_t *ptr)
    __attribute__((__always_inline__))
    __attribute__((__nonnull__))
    __attribute__((__nothrow__));

/*
 * Strings
 */

/**
 * @brief make a string that is shared among VMs.
 *
 * The returned string is not modifiable.   Make a copy if you need.  Also note
 * that the value  lives outside of your  object space; do not store  it on any
 * arrays or hashes or anything.
 *
 * @param[in] str string to share
 * @returns a shared frozen string with identical content of str
 */
extern VALUE rb_intervm_str(VALUE str);

/**
 * @brief finish an intervm string
 *
 * When an  intervm string is  no longer needed  -- GCed, made  independent for
 * some reason, etc -- then call it.
 *
 * @param[in] self string no longer shared
 */
extern void rb_intervm_str_descend(VALUE self);

/**
 * @brief reverse of descend
 *
 * This needs to be called when a  new object starts sharing the argument if it
 * is an intervm string, but I think  you cannot tell if an arbitrary string is
 * intervm or not,  so call it liberally anyway.  Does no  harm for normal ones
 * until they are not string.
 *
 * @param[in] self string to be ascended
 */
extern void rb_intervm_str_ascend(VALUE self);

/*
 * Wormholes
 */

/**
 * @brief creates a wormhole
 * @returns a wormhole created.
 *
 * A wormhole is much like a pipe.   Once created, a VM can send something from
 * it, and another VM can receive the info through it.  Every VMs has their own
 * wormhole at the beginning of their execution.
 *
 * @code
 *
 * vm = RubyVM.new("ruby", "-e RubyVM.current.recv # => gets foo")
 * vm.start.send "foo"
 *
 * @endcode
 *
 * But this is not so convenient.  You can also create a dedicated wormhole any
 * time you want, and that  also can be sent/received through another wormhole.
 * With this you can handshake a session between/among any VMs.
 *
 * @code
 *
 * # vm1 and vm2 can communicate this way, by not directly knowing each other
 * vm1 = RubyVM.new("ruby", "-e RubyVM.current.send RubyVM::Wormhole.new")
 * vm2 = RubyVM.new("ruby", "-e RubyVM.current.recv # => ^ this wormhole")
 * vm1.start
 * vm2.start
 * vm2.send vm1.recv
 *
 * @endcode
 */
extern VALUE rb_intervm_wormhole_new(void);

/**
 * @brief sends something through a wormhole
 * @param[out]  hole  target wormhole
 * @param[in]   obj   an immediate, a string, or another wormhole
 * @returns hole
 */
extern VALUE rb_intervm_wormhole_send(VALUE hole, VALUE obj);

/**
 * @brief recieves something through a wormhole (blocking version)
 * @param[out]  hole  target wormhole
 * @returns something from another side of the hole
 */
extern VALUE rb_intervm_wormhole_recv(VALUE hole);

/**
 * @brief nonblocking variant of recv
 * @param[out]  hole       target wormhole
 * @param[in]   ifnone     nothing-cen-be-read marker  
 * @retval      ifnone     nothing can be read
 * @retval      otherwise  something read
 */
extern VALUE rb_intervm_wormhole_peek(VALUE hole, VALUE ifnone);

/**
 * @brief needed by rb_thread_trap_pending()
 * @param[in]   hole  target wormhole
 * @retval      1     buffer empty
 * @retval      0     buffer loaded
 */
extern int rb_intervm_wormhole_is_empty(VALUE hole);

/** Expected to be called somewhere inside rb_vm_init(). */
extern void InitVM_Wormhole(void);

/** Does nothing but calles anyway */
extern void Init_Wormhole(void);

/*
 * Initializers
 */

/** Expected to be called somewhere inside rb_sysinit(). */
extern void Init_intervm(void);

/** Expected to be called somewhere inside rb_vm_init(). */
extern void InitVM_intervm(void);

/* 
 * inline function implementations
 */

#ifdef _WIN32

rb_atomic_t
rb_atomic_cas(ptr, old, set)
    rb_atomic_t *ptr, old, set;
{
    return InterlockedCompareExchange(ptr, old, set);
}

rb_atomic_t
rb_atomic_inc(ptr)
    rb_atomic_t *ptr;
{
    return InterlockedIncrement(ptr);
}

rb_atomic_t
rb_atomic_dec(ptr)
    rb_atomic_t *ptr;
{
    return InterlockedDecrement(ptr);
}

#elif defined(__GNUC__)

rb_atomic_t
rb_atomic_cas(ptr, old, set)
    rb_atomic_t *ptr, old, set;
{
    return __sync_val_compare_and_swap(ptr, old, set);
}

rb_atomic_t
rb_atomic_inc(ptr)
    rb_atomic_t *ptr;
{
    return __sync_fetch_and_add(ptr, 1);
}

rb_atomic_t
rb_atomic_dec(ptr)
    rb_atomic_t *ptr;
{
    return __sync_fetch_and_sub(ptr, 1);
}

#else
#error if yourcompiler supports atomic operations, write your own code.
/* Codes below are not atomic. */

rb_atomic_t
rb_atomic_cas(ptr, old, set)
    rb_atomic_t *ptr, old, set;
{
    rb_atomic_t tmp = *ptr;
    if (tmp == old)
        *ptr = set;
    return tmp;
}

rb_atomic_t
rb_atomic_inc(ptr)
    rb_atomic_t *ptr;
{
    return *ptr++;
}

rb_atomic_t
rb_atomic_dec(ptr)
    rb_atomic_t *ptr;
{
    return *ptr--;
}

#endif

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
