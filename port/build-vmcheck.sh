#!/usr/bin/env bash
set -euo pipefail
source=/work/ruby-4.0.7-glibc
build=$(mktemp -d /tmp/ruby-filc-vmcheck-XXXXXX)
printf '%s\n' "$build" > /work/ta/vmcheck-build-path.txt
git -c safe.directory="$source" -C "$source" archive HEAD | tar -x -C "$build"
cd "$build"
export PKG_CONFIG=/opt/fil/bin/pkg-config
export PKG_CONFIG_LIBDIR=/opt/fil/lib/pkgconfig:/opt/fil/share/pkgconfig
CC=/opt/fil/bin/filcc CXX=/opt/fil/bin/fil++ CPPFLAGS=-DVM_CHECK_MODE=1 ./configure --disable-shared --disable-yjit --disable-zjit --without-jit --without-valgrind --without-jemalloc --with-coroutine=ucontext --disable-install-doc --with-opt-dir=/opt/fil --prefix="$build/install"
make -j4 miniruby
./miniruby /work/probes/ruby/protected-callcache.rb
