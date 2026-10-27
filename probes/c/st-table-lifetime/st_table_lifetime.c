#include <ruby.h>
#include <ruby/st.h>

static int
mark_entry(st_data_t key, st_data_t value, st_data_t unused)
{
    rb_gc_mark((VALUE)key);
    rb_gc_mark((VALUE)value);
    return ST_CONTINUE;
}

static void
mark_table(void *ptr)
{
    st_foreach(ptr, mark_entry, 0);
}

static void
free_table(void *ptr)
{
    st_free_table(ptr);
}

static size_t
table_memsize(const void *ptr)
{
    return st_memsize(ptr);
}

static const rb_data_type_t table_type = {
    "st_table_lifetime",
    {mark_table, free_table, table_memsize},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static st_table *
table_get(VALUE self)
{
    st_table *table;
    TypedData_Get_Struct(self, st_table, &table_type, table);
    return table;
}

static VALUE
table_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &table_type, st_init_numtable());
}

static VALUE
table_aset(VALUE self, VALUE key, VALUE value)
{
    st_insert(table_get(self), (st_data_t)key, (st_data_t)value);
    return value;
}

static VALUE
table_delete(VALUE self, VALUE key)
{
    st_data_t k = (st_data_t)key, value;
    return st_delete(table_get(self), &k, &value) ? (VALUE)value : Qnil;
}

static VALUE
table_clear(VALUE self)
{
    st_clear(table_get(self));
    return self;
}

static VALUE
table_shift(VALUE self)
{
    st_data_t key, value;
    if (!st_shift(table_get(self), &key, &value)) return Qnil;
    return rb_ary_new_from_args(2, (VALUE)key, (VALUE)value);
}

static int
delete_update(st_data_t *key, st_data_t *value, st_data_t unused, int existing)
{
    return ST_DELETE;
}

static VALUE
table_update_delete(VALUE self, VALUE key)
{
    return st_update(table_get(self), (st_data_t)key, delete_update, 0) ? Qtrue : Qfalse;
}

static int
delete_if_entry(st_data_t key, st_data_t value, st_data_t unused)
{
    return RTEST(rb_yield_values(2, (VALUE)key, (VALUE)value)) ? ST_DELETE : ST_CONTINUE;
}

static VALUE
table_delete_if(VALUE self)
{
    st_foreach(table_get(self), delete_if_entry, 0);
    return self;
}

static int
collect_entry(st_data_t key, st_data_t value, st_data_t pairs)
{
    rb_ary_push((VALUE)pairs, rb_ary_new_from_args(2, (VALUE)key, (VALUE)value));
    return ST_CONTINUE;
}

static VALUE
table_to_a(VALUE self)
{
    VALUE pairs = rb_ary_new();
    st_foreach(table_get(self), collect_entry, (st_data_t)pairs);
    return pairs;
}

void
Init_st_table_lifetime(void)
{
    VALUE klass = rb_define_class("NativeLifetimeTable", rb_cObject);
    rb_define_alloc_func(klass, table_alloc);
    rb_define_method(klass, "[]=", table_aset, 2);
    rb_define_method(klass, "delete", table_delete, 1);
    rb_define_method(klass, "clear", table_clear, 0);
    rb_define_method(klass, "shift", table_shift, 0);
    rb_define_method(klass, "update_delete", table_update_delete, 1);
    rb_define_method(klass, "delete_if", table_delete_if, 0);
    rb_define_method(klass, "to_a", table_to_a, 0);
}
