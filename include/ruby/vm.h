/**********************************************************************

  ruby/vm.h -

  $Author$
  created at: Sat May 31 15:17:36 2008

  Copyright (C) 2008 Yukihiro Matsumoto

**********************************************************************/

#ifndef RUBY_VM_H
#define RUBY_VM_H 1

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#include <stddef.h>

#define HAVE_MVM 1

/* VM type declaration */
typedef struct rb_vm_struct ruby_vm_t;

/* core API */
ruby_vm_t *ruby_vm_new(int argc, char *argv[]);
int ruby_vm_exit_status(ruby_vm_t *vm);
int ruby_vm_exit_signal(ruby_vm_t *vm);
int ruby_vm_run(ruby_vm_t *vm);
int ruby_vm_spawn(ruby_vm_t *vm);
int ruby_vm_run_node(ruby_vm_t *vm, void *n);
int ruby_vm_exec_node(ruby_vm_t *vm, void *n);
int ruby_vm_join(ruby_vm_t *vm);
int ruby_vm_cleanup(ruby_vm_t *vm, int ex);
int ruby_vm_destruct(ruby_vm_t *vm);
int ruby_vm_alone(void);
int ruby_vm_main_p(ruby_vm_t *vm);
void ruby_vm_die(ruby_vm_t *vm);
int ruby_vm_call(ruby_vm_t *vm, void (*func)(void *), void *arg);

/* initialize API */
ruby_vm_t *ruby_init(void);
int ruby_vm_init(ruby_vm_t *vm);
int ruby_vm_init_add_argv(ruby_vm_t *vm, const char *arg);
int ruby_vm_init_add_library(ruby_vm_t *vm, const char *lib);
int ruby_vm_init_add_library_path(ruby_vm_t *vm, const char *path);
int ruby_vm_init_add_expression(ruby_vm_t *vm, const char *expr);
int ruby_vm_init_script(ruby_vm_t *vm, const char *script);
int ruby_vm_init_verbose(ruby_vm_t *vm, int verbose_p);
int ruby_vm_init_debug(ruby_vm_t *vm, int debug);
int ruby_vm_init_add_initializer(ruby_vm_t *vm, void (*initializer)(ruby_vm_t *));
int ruby_vm_init_stdin(ruby_vm_t *vm, int fd);
int ruby_vm_init_stdout(ruby_vm_t *vm, int fd);
int ruby_vm_init_stderr(ruby_vm_t *vm, int fd);

/* other API */
void ruby_vm_foreach(int (*)(ruby_vm_t *, void *), void *); /* returning false stops iteration */
void **ruby_vm_specific_ptr(int);

#ifdef __GNUC__
__attribute__((__pure__, __warn_unused_result__))
#endif
/**
   Get a pointer to a VM specific storage for VM _vm_.  A key shall be
   initialized using rb_vm_key_create() beforehand.

   @param[in] vm where to seek a pointer.  Touches its internals when
       a key is new to this vm (storage created then).
   @param[in] key  which storage.
   @returns a pointer to a VM specific storage.
 */
void **rb_vm_specific_ptr_for_specific_vm(ruby_vm_t *vm, int key);

/**
   ruby_vm_at_exit registers a function _func_ to be invoked when a VM
   passed away.  Functions registered this way runs in reverse
   order of registeration, just like END {} block does.  The
   difference is its timing to be triggerd. ruby_vm_at_exit functions
   runs when a VM _passed_ _away_, while END {} blocks runs just
   _before_ a VM _is_ _passing_ _away_.

   @param[in] func the function to register.
 */
void ruby_vm_at_exit(void(*func)(ruby_vm_t *));

/* system level initializer */

void ruby_sysinit(int *, char ***);

#if (defined(__APPLE__) || defined(__NeXT__)) && defined(__MACH__)
/* to link startup code with ObjC support */
#define RUBY_GLOBAL_SETUP static void objcdummyfunction(void) {objc_msgSend();}
#else
#define RUBY_GLOBAL_SETUP
#endif


#ifdef __ia64
void ruby_init_stack(volatile void *, void *);
#define ruby_init_stack(addr) ruby_init_stack(addr, rb_ia64_bsp())
#else
void ruby_init_stack(volatile void *);
#endif
#define RUBY_INIT_STACK \
    void *variable_in_this_stack_frame; \
    ruby_init_stack(&variable_in_this_stack_frame);

struct rb_objspace;
void *rb_objspace_xmalloc(struct rb_objspace *objspace, size_t size);
void *rb_objspace_xrealloc(struct rb_objspace *objspace, void *ptr, size_t size);
void *rb_objspace_xmalloc2(struct rb_objspace *objspace, size_t n, size_t size);
void *rb_objspace_xrealloc2(struct rb_objspace *objspace, void *ptr, size_t n, size_t size);
void rb_objspace_xfree(struct rb_objspace *objspace, void *ptr);

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_VM_H */
