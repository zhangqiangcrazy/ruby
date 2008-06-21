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

/* VM type declaration */
typedef struct rb_vm_struct ruby_vm_t;

/* core API */
VALUE *ruby_vm_verbose_ptr(ruby_vm_t *);
VALUE *ruby_vm_debug_ptr(ruby_vm_t *);

VALUE ruby_vm_get_argv(ruby_vm_t*);
void ruby_vm_set_argv(ruby_vm_t *, int, char **);
const char *ruby_vm_get_inplace_mode(ruby_vm_t *);
void ruby_vm_set_inplace_mode(ruby_vm_t *, const char *);
void ruby_vm_prog_init(ruby_vm_t *);
VALUE ruby_vm_process_options(ruby_vm_t *, int, char **);
VALUE ruby_vm_parse_options(ruby_vm_t *, int, char **);

void rb_vm_clear_trace_func(ruby_vm_t *);
void rb_vm_thread_terminate_all(ruby_vm_t *);

ruby_vm_t *ruby_vm_new(void);
int ruby_vm_run(ruby_vm_t *, VALUE);
int ruby_vm_destruct(ruby_vm_t *vm);

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_VM_H */
