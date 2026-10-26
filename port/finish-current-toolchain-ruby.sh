#!/usr/bin/env bash
set -euo pipefail
build=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
cd "$build"
export PATH=/compiler/tools/bin:/usr/bin:/bin
export CC=/compiler/source/build/bin/clang
export CXX=/compiler/source/build/bin/clang++
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_LIBDIR=/compiler/source/pizfix/lib/pkgconfig
export LANG=C.UTF-8
unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS LIBS LD_LIBRARY_PATH
prefix=/compiler/source/pizfix
if [[ ! -e "$prefix/ssl/cert.pem" ]]; then
  ln -s /etc/ssl/certs/ca-certificates.crt "$prefix/ssl/cert.pem"
fi
mkdir -p "$prefix/share"
if [[ ! -e "$prefix/share/zoneinfo" ]]; then
  ln -s /usr/share/zoneinfo "$prefix/share/zoneinfo"
fi
./configure --enable-shared --disable-yjit --disable-zjit --without-jit \
  --without-valgrind --without-jemalloc --with-coroutine=ucontext \
  --disable-install-doc --with-opt-dir="$prefix" \
  --prefix="$(dirname "$build")/install" --with-baseruby=/usr/bin/ruby
make -j4
make install
ruby="$(dirname "$build")/install/bin/ruby"
"$ruby" -ropenssl -rpsych -rzlib -rfiddle -rjson -e '
  puts RUBY_DESCRIPTION
  puts OpenSSL::OPENSSL_LIBRARY_VERSION
  puts Psych::LIBYAML_VERSION
  puts Zlib::ZLIB_VERSION
  puts File.read("/proc/self/maps").lines.grep(/\.so/).map { |line| line.split.last }.uniq
'
