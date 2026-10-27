#!/usr/bin/env bash
set -euo pipefail

ruby -ropenssl -rpsych -rzlib -rjson -rbundler -rnet/http -rfiddle -rsocket -e '
  puts RUBY_DESCRIPTION
  raise unless RUBY_VERSION == "4.0.9"
  raise unless RbConfig::CONFIG.fetch("CC") == ENV.fetch("FILC_CC", "/opt/fil/bin/filcc")
  raise unless Encoding.default_external == Encoding::UTF_8
  raise unless Addrinfo.getaddrinfo("localhost", "ssh", :INET, :STREAM).all? { |address| address.ip_port == 22 }
  objects = Array.new(100_000) { |i| {i => i.to_s} }
  GC.start
  raise unless objects[123][123] == "123"
  fibers = Array.new(1000) { |i| Fiber.new { Fiber.yield(i); i * 2 } }
  raise unless fibers.map(&:resume).sum == 499500
  GC.start
  raise unless fibers.map(&:resume).sum == 999000
  strlen = Fiddle::Function.new(Fiddle::Handle::DEFAULT["strlen"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_SIZE_T)
  raise unless strlen.call("Fil-C") == 5
  raise unless JSON.parse(JSON.generate({"ok" => true})).fetch("ok")
  raise unless Psych.safe_load(Psych.dump({"ok" => true})).fetch("ok")
  raise unless Zlib::Inflate.inflate(Zlib::Deflate.deflate("Fil-C")) == "Fil-C"
  raise unless OpenSSL::Digest::SHA256.hexdigest("Fil-C").size == 64
  uri = URI("https://rubygems.org/api/v1/gems/rake.json")
  raise unless JSON.parse(Net::HTTP.get(uri)).fetch("name") == "rake"
  puts "Ruby 4.0.9, GC, fibers, Fiddle, JSON, YAML, zlib, OpenSSL, Bundler, and HTTPS passed"
'

mkdir -p /tmp/filc-probe
cd /tmp/filc-probe
cat > filc_probe.c <<'C'
#include <ruby.h>
#include <stdfil.h>
#include <stdlib.h>

#ifndef __FILC__
#error Native extensions must use Fil-C
#endif

static VALUE hello(VALUE self) {
    return rb_str_new_cstr("Fil-C native extension");
}

static VALUE overflow(VALUE self) {
    volatile char *p = malloc(1);
    volatile size_t offset = zlength((char *)p);
    p[offset] = 42;
    free((void *)p);
    return Qnil;
}

void Init_filc_probe(void) {
    rb_define_global_function("filc_hello", hello, 0);
    rb_define_global_function("filc_overflow", overflow, 0);
}
C
ruby -rmkmf -e 'create_makefile("filc_probe")'
make
ruby -I. -rfilc_probe -e 'raise unless filc_hello == "Fil-C native extension"'
set +e
ruby -I. -rfilc_probe -e 'filc_overflow' > panic.log 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo 'Expected Fil-C to reject the native extension buffer overflow' >&2
    exit 1
fi
grep -q 'filc safety error' panic.log
printf 'Native extension build, load, and buffer-overflow detection passed (exit %s)\n' "$status"
