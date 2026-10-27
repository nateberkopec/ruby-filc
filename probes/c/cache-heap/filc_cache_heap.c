#include <ruby.h>
#include <stdfil.h>

static VALUE
heap_dump(VALUE self, VALUE fd)
{
    zdump_heap(NUM2INT(fd));
    return Qnil;
}

static VALUE
scavenge(VALUE self)
{
    zscavenge_synchronously();
    return Qnil;
}

/* Deliberately bypass Ruby's logical GC state for retention diagnostics. */
static VALUE
collect(VALUE self)
{
    zgc_cycle_number cycle = zgc_request_fresh();
    zgc_wait(cycle);
    return ULL2NUM(cycle);
}

static VALUE
object_address(VALUE self, VALUE object)
{
    return ULL2NUM((uintptr_t)object);
}

void
Init_filc_cache_heap(void)
{
    VALUE mod = rb_define_module("FilcCacheHeap");
    rb_define_singleton_method(mod, "dump", heap_dump, 1);
    rb_define_singleton_method(mod, "scavenge", scavenge, 0);
    rb_define_singleton_method(mod, "collect", collect, 0);
    rb_define_singleton_method(mod, "address", object_address, 1);
}
