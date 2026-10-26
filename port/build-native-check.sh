#!/usr/bin/env bash
set -euo pipefail
source=/work/ruby-4.0.7-glibc
build=$(mktemp -d /tmp/ruby-filc-native-check-XXXXXX)
printf '%s\n' "$build" > /work/ta/native-check-build-path.txt
git -c safe.directory="$source" -C "$source" archive HEAD | tar -x -C "$build"
cd "$build"
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
CC=/usr/bin/gcc CXX=/usr/bin/g++ CPPFLAGS=-DVM_CHECK_MODE=1 ./configure --disable-shared --disable-yjit --disable-zjit --without-jit --without-valgrind --without-jemalloc --with-coroutine=ucontext --disable-install-doc --prefix="$build/install"
make -j4 miniruby
set +e
timeout -k 15 600 make btest > /work/ta/btest-native-checked.log 2>&1
result=$?
printf '%s\n' "$result" > /work/ta/btest-native-checked.status
if [[ $result -ne 0 ]]; then exit "$result"; fi
timeout -k 10 180 ./miniruby /work/tmetaclass-publication.rb > /work/ta/metaclass-publication-native-checked.log 2>&1
result=$?
printf '%s\n' "$result" > /work/ta/metaclass-publication-native-checked.status
exit "$result"
