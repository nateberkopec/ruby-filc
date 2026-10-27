#!/usr/bin/env bash
# Build-only experiment: preserve installed controls and all Fil-C safety checks.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
archive=$(realpath "${1:?verified Ruby archive required}")
build=$(realpath -m "${2:?new build directory required}")
baseruby=$(realpath "${3:?stock bootstrap Ruby required}")
runtime_prefix=$(realpath "${4:?existing matching Fil-C runtime prefix required}")
compiler_prefix=${FILC_PREFIX:-/opt/fil}
expected=$(awk -F= '$1 == "ARG RUBY_SHA256" { print $2 }' "$root/example/Dockerfile")
printf '%s  %s\n' "$expected" "$archive" | sha256sum -c -
# Refuse reuse: old object files would invalidate a compile-flag comparison.
mkdir "$build"
tar -xf "$archive" -C "$build" --strip-components=1
cd "$build"
patch -p1 < "$root/ruby-4.0.9-filc.patch"
export CC="$compiler_prefix/bin/filcc" CXX="$compiler_prefix/bin/fil++"
export PKG_CONFIG="$compiler_prefix/bin/pkg-config"
export PKG_CONFIG_LIBDIR="$compiler_prefix/lib/pkgconfig:$compiler_prefix/share/pkgconfig"
unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS LIBS LD_LIBRARY_PATH LD_PRELOAD PKG_CONFIG_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH GEM_HOME GEM_PATH BUNDLE_APP_CONFIG RUBYOPT
unset cflags optflags debugflags warnflags hardenflags
export XLDFLAGS='-Wl,-z,pack-relative-relocs'
# The prefix supplies unchanged Ruby libraries and native gems for the library
# override. This script never installs into or modifies that prefix.
./configure --prefix="$runtime_prefix" --enable-shared --disable-yjit --disable-zjit --without-jit \
    --without-valgrind --without-jemalloc --with-coroutine=ucontext --with-opt-dir="$compiler_prefix" \
    --disable-install-doc --with-baseruby="$baseruby" debugflags=-g0
make -j"${BUILD_JOBS:-8}"
make btest
make test-all TESTS='ruby/test_array.rb ruby/test_hash.rb ruby/test_string.rb ruby/test_class.rb ruby/test_object.rb ruby/test_variable.rb ruby/test_ractor.rb'
make test-all TESTS='ruby/test_backtrace.rb ruby/test_exception.rb'
