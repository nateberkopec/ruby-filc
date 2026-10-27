#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
archive=${1:?Verified Ruby source archive required}
prefix=${2:?Installation prefix required}
version=$(awk -F= '$1 == "ARG RUBY_VERSION" { print $2 }' "$root/example/Dockerfile")
sha=$(awk -F= '$1 == "ARG RUBY_SHA256" { print $2 }' "$root/example/Dockerfile")
printf '%s  %s\n' "$sha" "$archive" | sha256sum -c -
test ! -e "$prefix"
build=$(mktemp -d /tmp/ruby-stock-runtime-XXXXXX)
tar -xf "$archive" -C "$build"
cd "$build/ruby-$version"
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export CC=/usr/bin/gcc CXX=/usr/bin/g++ PKG_CONFIG=/usr/bin/pkg-config
unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS LIBS LD_LIBRARY_PATH LD_PRELOAD PKG_CONFIG_LIBDIR PKG_CONFIG_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH GEM_HOME GEM_PATH BUNDLE_APP_CONFIG RUBYOPT
./configure --prefix="$prefix" --enable-shared --disable-yjit --disable-zjit --without-jit --without-valgrind --without-jemalloc --with-coroutine=ucontext --disable-install-doc --with-baseruby=/usr/bin/ruby
make -j"${BUILD_JOBS:-4}"
make install
"$prefix/bin/ruby" -v
readelf -l "$prefix/bin/ruby" | grep 'Requesting program interpreter'
"$prefix/bin/ruby" -rrbconfig -rjson -ropenssl -e 'abort "unexpected compiler" unless RbConfig::CONFIG.fetch("CC") == "/usr/bin/gcc"; puts RbConfig::CONFIG.fetch("configure_args")'
