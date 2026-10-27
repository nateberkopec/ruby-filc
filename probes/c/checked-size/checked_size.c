#include <ruby.h>
#include <ruby/internal/memory.h>

static VALUE
checked_multiply(VALUE self, VALUE left, VALUE right)
{
    return SIZET2NUM(rbimpl_size_mul_or_raise(NUM2SIZET(left), NUM2SIZET(right)));
}

static VALUE
checked_add(VALUE self, VALUE left, VALUE right)
{
    return SIZET2NUM(rbimpl_size_add_or_raise(NUM2SIZET(left), NUM2SIZET(right)));
}

static VALUE
checked_bytes(VALUE self, VALUE count)
{
    return SIZET2NUM(rbimpl_size_mul_or_raise(NUM2SIZET(count), 1));
}

static VALUE
checked_values(VALUE self, VALUE count)
{
    return SIZET2NUM(rbimpl_size_mul_or_raise(NUM2SIZET(count), sizeof(VALUE)));
}

void
Init_checked_size(void)
{
    VALUE module = rb_define_module("CheckedSize");
    rb_define_const(module, "MAX", SIZET2NUM(SIZE_MAX));
    rb_define_const(module, "VALUE_BYTES", SIZET2NUM(sizeof(VALUE)));
    rb_define_singleton_method(module, "multiply", checked_multiply, 2);
    rb_define_singleton_method(module, "add", checked_add, 2);
    rb_define_singleton_method(module, "bytes", checked_bytes, 1);
    rb_define_singleton_method(module, "values", checked_values, 1);
}
