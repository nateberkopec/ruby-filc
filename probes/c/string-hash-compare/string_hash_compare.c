#include <ruby.h>

static VALUE
hash_compare(VALUE self, VALUE left, VALUE right)
{
    Check_Type(left, T_STRING);
    Check_Type(right, T_STRING);
    return rb_str_hash_cmp(left, right) == 0 ? Qtrue : Qfalse;
}

void
Init_string_hash_compare(void)
{
    VALUE mod = rb_define_module("StringHashCompare");
    rb_define_singleton_method(mod, "equal?", hash_compare, 2);
}
