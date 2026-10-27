#!/usr/bin/env bash
set -euo pipefail
archive=${1:?Pinned Ruby source archive required}
version=$(awk -F= '$1 == "ARG RUBY_VERSION" { print $2 }' /work/example/Dockerfile)
sha=$(awk -F= '$1 == "ARG RUBY_SHA256" { print $2 }' /work/example/Dockerfile)
printf '%s  %s\n' "$sha" "$archive" | sha256sum -c -
root=$(mktemp -d /compiler/ruby-stock-control-XXXXXX)
tar -xf "$archive" -C "$root"
build="$root/ruby-$version"
printf '%s\n' "$build" > "/work/ta/stock-ruby-$version-build-path.txt"
cd "$build"
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CC=/usr/bin/gcc CXX=/usr/bin/g++ PKG_CONFIG=/usr/bin/pkg-config
unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS LIBS LD_LIBRARY_PATH LD_PRELOAD PKG_CONFIG_LIBDIR PKG_CONFIG_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH
./configure --disable-shared --disable-yjit --disable-zjit --without-jit --without-valgrind --without-jemalloc --with-coroutine=ucontext --disable-install-doc --prefix="$root/install" --with-baseruby=/usr/bin/ruby
make -j4 miniruby
./miniruby -v
readelf -l miniruby | grep 'Requesting program interpreter'
cp miniruby "$root/miniruby-stock-unmodified"
