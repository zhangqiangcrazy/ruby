/**********************************************************************

  mvm.c - Ruby/MVM C API

  $Author:  $
  created at: Sun Aug 31 22:27:03 2008

  Copyright (C) 2008 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/vm.h"
#include "vm_core.h"
#include "eval_intern.h"

#define RUBY_VM_OBJECT(vm, name) \
  (*((VALUE *)ruby_vm_specific_ptr(vm, rb_vmkey_##name)))

static void vmmgr_add(rb_vm_t *vm);
static void vmmgr_del(rb_vm_t *vm);

static int vm_join(rb_vm_t *vm);

/* core API */

rb_vm_t *
ruby_vm_new(int argc, char *argv[])
{
    rb_vm_t *vm = ruby_init();

    if (!vm && !(vm = ruby_make_bare_vm())) return 0;
    vm->argc = argc;
    vm->argv = argv;
    vmmgr_add(vm);

    return vm;
}

int
ruby_vm_join(rb_vm_t *vm)
{
    return vm_join(vm);
}

int
ruby_vm_destruct(rb_vm_t *vm)
{
#if 0 /* @shyouhei saves this from trunk... */
    RUBY_FREE_ENTER("vm");
    if (vm) {
	rb_thread_t *th = vm->main_thread;
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
	struct rb_objspace *objspace = vm->objspace;
#endif
	rb_gc_force_recycle(vm->self);
	vm->main_thread = 0;
	if (th) {
	    thread_free(th);
	}
	if (vm->living_threads) {
	    st_free_table(vm->living_threads);
	    vm->living_threads = 0;
	}
	rb_thread_lock_unlock(&vm->global_vm_lock);
	rb_thread_lock_destroy(&vm->global_vm_lock);
	ruby_xfree(vm);
#if defined(ENABLE_VM_OBJSPACE) && ENABLE_VM_OBJSPACE
	if (objspace) {
	    rb_objspace_free(objspace);
	}
#endif
    }
    RUBY_FREE_LEAVE("vm");
    return 0;
}
#endif
    if (ruby_vmptr_destruct(vm)) {
	vmmgr_del(vm);
	free(vm);
    }
    return 0;
}


/* initialize API */
struct rb_vm_options *rb_vm_options_init(struct rb_vm_options *opt);
struct rb_vm_options *rb_vmptr_init_options(rb_vm_t *vm);

#define vm_init_options(vm) rb_vmptr_init_options(vm)

/*
 * ARGV
 */
int
ruby_vm_init_add_argv(rb_vm_t *vm, const char *arg)
{
    void ruby_options_add_to_argv(struct rb_vm_options *, const char *);
    ruby_options_add_to_argv(vm_init_options(vm), arg);
    return 1;
}

int
ruby_vm_init_add_library(rb_vm_t *vm, const char *lib)
{
    void ruby_options_add_library(struct rb_vm_options *, const char *);
    ruby_options_add_library(vm_init_options(vm), lib);
    return 1;
}

int
ruby_vm_init_add_library_path(rb_vm_t *vm, const char *path)
{
    void ruby_options_add_library_path(struct rb_vm_options *, const char *);
    ruby_options_add_library_path(vm_init_options(vm), path);
    return 1;
}

int
ruby_vm_init_add_expression(rb_vm_t *vm, const char *expr)
{
    void ruby_options_add_expression(struct rb_vm_options *, const char *);
    ruby_options_add_expression(vm_init_options(vm), expr);
    return 1;
}

int
ruby_vm_init_script(rb_vm_t *vm, const char *script)
{
    if (script) return 0;
    vm_init_options(vm)->script = script;
    return 1;
}

int
ruby_vm_init_verbose(rb_vm_t *vm, int verbose_p)
{
    vm_init_options(vm)->verbose = verbose_p;
    return 1;
}

int
ruby_vm_init_debug(rb_vm_t *vm, int debug)
{
    vm_init_options(vm)->debug = debug;
    return 1;
}

struct rb_vm_initializer_func {
    void (*func)(rb_vm_t *);
    struct rb_vm_initializer_func *next;
};

struct rb_vm_initializer {
    struct rb_vm_initializer_func *head, **tail;
};

int
ruby_vm_init_add_initializer(rb_vm_t *vm, void (*initializer)(rb_vm_t *))
{
    struct rb_vm_initializer_func *f;
    struct rb_vm_initializer **init = &vm_init_options(vm)->initializer, *i;

    if (!(i = *init)) {
	(*init) = i = malloc(sizeof(*i));
	i->head = 0;
	i->tail = &i->head;
    }
    f = malloc(sizeof(*f));
    f->func = initializer;
    f->next = 0;
    *i->tail = f;
    i->tail = &f->next;
    return 1;
}

void
ruby_vm_init_call_initializer(rb_vm_t *vm)
{
    struct rb_vm_initializer *init = vm_init_options(vm)->initializer;
    struct rb_vm_initializer_func *f;

    if (!init) return;
    for (f = init->head; f; f = f->next) {
	(*f->func)(vm);
    }
}

int
ruby_vm_init_stdin(rb_vm_t *vm, int fd)
{
    vm_init_options(vm)->stdfds[0] = fd;
    return 1;
}

int
ruby_vm_init_stdout(rb_vm_t *vm, int fd)
{
    vm_init_options(vm)->stdfds[1] = fd;
    return 1;
}

int
ruby_vm_init_stderr(rb_vm_t *vm, int fd)
{
    vm_init_options(vm)->stdfds[2] = fd;
    return 1;
}


/* specific key management API */

#define MVM_CRITICAL(lock, expr) do { \
    ruby_native_thread_lock(&(lock)); \
    {expr;} \
    ruby_native_thread_unlock(&(lock)); \
} while (0)

static struct {
    int last;
    rb_thread_lock_t lock;
} specific_key = {((ruby_builtin_object_count + 8) & ~7)};

int
rb_vm_key_count(void)
{
    return specific_key.last;
}

int
rb_vm_key_create(void)
{
    int key;
    MVM_CRITICAL(specific_key.lock, {
	key = specific_key.last++;
    });
    return key;
}

void **
rb_vm_specific_ptr_for_specific_vm(rb_vm_t *vm, int key)
{
    void **ptr;
    long len;

    ptr = vm->specific_storage.ptr;
    len = vm->specific_storage.len;
    if (!ptr || len <= key) {
	long newlen = (key + 8) & ~7;
	ptr = realloc(ptr, sizeof(void *) * newlen);
	vm->specific_storage.ptr = ptr;
	vm->specific_storage.len = newlen;
	MEMZERO(&ptr[len], void *, newlen - len);
    }
    return &ptr[key];
}

void **
ruby_vm_specific_ptr(int key)
{
    rb_vm_t *vm = GET_VM();
    if (!vm) return 0;
    return rb_vm_specific_ptr_for_specific_vm(vm, key);
}

/* at exit */

void
ruby_vm_at_exit(void (*func)(rb_vm_t *vm))
{
    rb_ary_push((VALUE)&GET_VM()->at_exit, (VALUE)func);
}

/* VM management */

static struct {
    rb_thread_lock_t lock;
    struct vm_list_struct {
	struct vm_list_struct *next;
	rb_vm_t *vm;
    } *list;
    rb_vm_t *main;
} vm_manager;

void
Init_vmmgr(void)
{
    /* vm_manager */
    ruby_native_thread_lock_initialize(&vm_manager.lock);

    /* specific_key */
    ruby_native_thread_lock_initialize(&specific_key.lock);
    specific_key.last = (ruby_builtin_object_count + 8) & ~7;
}

int
ruby_vm_alone(void)
{
    int alone = 0;
    MVM_CRITICAL(vm_manager.lock, {
	struct vm_list_struct *entry = vm_manager.list;
	if (entry && !entry->next) alone = 1;
    });
    return alone;
}

int
ruby_vm_main_p(rb_vm_t *vm)
{
    return vm == vm_manager.main;
}

void
ruby_vmmgr_add(rb_vm_t *vm)
{
    vmmgr_add(vm);
}

static void
vmmgr_add(rb_vm_t *vm)
{
    struct vm_list_struct *entry =
      (struct vm_list_struct *)malloc(sizeof(struct vm_list_struct));

    entry->vm = vm;

    MVM_CRITICAL(vm_manager.lock, {
	if (vm_manager.main == 0) {
	    vm_manager.main = vm;
	}

	entry->next = vm_manager.list;
	vm_manager.list = entry;
    });
}

static void
vmmgr_del(rb_vm_t *vm)
{
    struct vm_list_struct *entry, *prev = 0;

    MVM_CRITICAL(vm_manager.lock, {
	entry = vm_manager.list;
	while (entry && entry->vm != vm) {
	    prev = entry;
	    entry = entry->next;
	}

	if (entry) {
	    if (prev) {
		prev->next = entry->next;
	    }
	    else {
		vm_manager.list = entry->next;
	    }
	    free(entry);
	}
    });
}

void
ruby_vm_foreach(int (*func)(rb_vm_t *, void *), void *arg)
{
    if (vm_manager.list) {
	MVM_CRITICAL(vm_manager.lock, {
	    struct vm_list_struct *entry = vm_manager.list;

	    while (entry) {
		if (func(entry->vm, arg) == 0) {
		    break;
		}
		entry = entry->next;
	    }
	});
    }
}

static int
vm_join(rb_vm_t *vm)
{
    st_table *living_threads = vm->living_threads;

    if (!living_threads) return 0;
    MVM_CRITICAL(vm_manager.lock, {
	struct vm_list_struct *entry = vm_manager.list;
	while (entry && entry->vm != vm) {
	    entry = entry->next;
	}
	if (entry) {
	    while (vm->living_threads) {
		ruby_native_cond_wait(&vm->global_vm_waiting, &vm_manager.lock);
	    }
	}
    });
    return 0;
}
