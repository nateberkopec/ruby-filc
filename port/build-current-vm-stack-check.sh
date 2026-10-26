#!/usr/bin/env bash
set -euo pipefail
source=/work/ruby-4.0.7-glibc
build=$(mktemp -d /compiler/ruby-frame-check-XXXXXX)
printf '%s\n' "$build" > /work/ta/vm-stack-checked-build-path.txt
git -c safe.directory="$source" -C "$source" archive filc-78e4bb7-recovered | tar -x -C "$build"
cd "$build"
patch -p1 < /work/port/vm-stack-clear-revised.patch
for file in vm.c vm_core.h vm_insnhelper.c; do cmp "$file" "$source/$file"; done
export PATH=/compiler/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_LIBDIR=/compiler/source/pizfix/lib/pkgconfig
export LANG=C.UTF-8
unset CFLAGS CXXFLAGS LDFLAGS LIBS LD_LIBRARY_PATH
CC=/compiler/source/build/bin/clang CXX=/compiler/source/build/bin/clang++ CPPFLAGS='-DVM_CHECK_MODE=1 -DVM_DEBUG_BP_CHECK=1' ./configure --disable-shared --disable-yjit --disable-zjit --without-jit --without-valgrind --without-jemalloc --with-coroutine=ucontext --disable-install-doc --with-opt-dir=/compiler/source/pizfix --prefix="$build/install" --with-baseruby=/usr/bin/ruby
make -j4 miniruby
