#include <ruby.h>
#include <stdfil.h>
#include "vm_core.h"

static VALUE
heap_dump(VALUE self, VALUE fd)
{
    zdump_heap(NUM2INT(fd));
    return Qnil;
}

static VALUE
object_address(VALUE self, VALUE object)
{
    return ULL2NUM((uintptr_t)object);
}

static VALUE
stack_info(VALUE self)
{
    rb_thread_t *thread = RTYPEDDATA_DATA(rb_thread_current());
    rb_execution_context_t *ec = thread->ec;
    return rb_ary_new_from_args(3, ULL2NUM((uintptr_t)ec->vm_stack),
                               SIZET2NUM(ec->vm_stack_size * sizeof(VALUE)),
                               ULL2NUM((uintptr_t)ec->cfp));
}

void
Init_filc_vm_stack_heap(void)
{
    VALUE mod = rb_define_module("FilcVmStackHeap");
    rb_define_singleton_method(mod, "dump", heap_dump, 1);
    rb_define_singleton_method(mod, "address", object_address, 1);
    rb_define_singleton_method(mod, "stack_info", stack_info, 0);
}
