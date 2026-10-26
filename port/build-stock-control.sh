#!/usr/bin/env bash
set -euo pipefail
archive=${1:?Ruby 4.0.7 source archive required}
printf '%s  %s\n' 47ef59413f7a4587ba6a6b78b14036eb5e36eec2ec0b90964801e88d56a3d375 "$archive" | sha256sum -c -
root=$(mktemp -d /compiler/ruby-stock-control-XXXXXX)
tar -xf "$archive" -C "$root"
build="$root/ruby-4.0.7"
printf '%s\n' "$build" > /work/ta/stock-ruby-build-path.txt
cd "$build"
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CC=/usr/bin/gcc CXX=/usr/bin/g++ PKG_CONFIG=/usr/bin/pkg-config
unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS LIBS LD_LIBRARY_PATH PKG_CONFIG_LIBDIR
./configure --disable-shared --disable-yjit --disable-zjit --without-jit --without-valgrind --without-jemalloc --with-coroutine=ucontext --disable-install-doc --prefix="$root/install" --with-baseruby=/usr/bin/ruby
make -j4 miniruby
./miniruby -v
readelf -l miniruby | grep 'Requesting program interpreter'
cp miniruby "$root/miniruby-stock-unmodified"
