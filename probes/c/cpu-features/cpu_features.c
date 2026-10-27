#include <ruby.h>

static VALUE
cpu_sse2(VALUE self)
{
#if defined(__x86_64__) && (defined(__GNUC__) || defined(__clang__))
    return __builtin_cpu_supports("sse2") ? Qtrue : Qfalse;
#else
    rb_raise(rb_eNotImpError, "this probe requires x86-64 GCC or Clang builtins");
#endif
}

static VALUE
cpu_initialize(VALUE self)
{
#if defined(__x86_64__) && (defined(__GNUC__) || defined(__clang__))
    __builtin_cpu_init();
    return cpu_sse2(self);
#else
    rb_raise(rb_eNotImpError, "this probe requires x86-64 GCC or Clang builtins");
#endif
}

void
Init_cpu_features(void)
{
    VALUE module = rb_define_module("CPUFeatures");
    rb_define_singleton_method(module, "sse2?", cpu_sse2, 0);
    rb_define_singleton_method(module, "initialize!", cpu_initialize, 0);
}
