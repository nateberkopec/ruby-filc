#!/usr/bin/env bash
set -euo pipefail
root=$(mktemp -d /compiler/ruby-current-port-XXXXXX)
printf '%s\n' "$root/ruby-4.0.7" > /work/ta/ruby-cme-current-toolchain-path.txt
cd "$root"
printf '%s  %s\n' 47ef59413f7a4587ba6a6b78b14036eb5e36eec2ec0b90964801e88d56a3d375 /work/ruby-4.0.7.tar.xz | sha256sum -c -
cp /work/ruby-4.0.7-filc.patch port.patch
cp /work/port/sources.txt sources.txt
sha256sum port.patch
printf 'Ruby source: '
git -c safe.directory=/work/ruby-4.0.7-glibc -C /work/ruby-4.0.7-glibc rev-parse HEAD
printf 'Compiler source: '
git -C /compiler/source rev-parse HEAD
/compiler/source/build/bin/clang --version
tar -xf /work/ruby-4.0.7.tar.xz
cd ruby-4.0.7
patch -p1 < ../port.patch
while IFS= read -r source; do
  cmp "$source" "/work/ruby-4.0.7-glibc/$source"
done < ../sources.txt
export PATH=/compiler/tools/bin:$PATH
export CC=/compiler/source/build/bin/clang
export CXX=/compiler/source/build/bin/clang++
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_LIBDIR=/compiler/source/pizfix/lib/pkgconfig
unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS LIBS LD_LIBRARY_PATH
./configure --enable-shared --disable-yjit --disable-zjit --without-jit \
  --without-valgrind --without-jemalloc --with-coroutine=ucontext \
  --disable-install-doc --with-opt-dir=/compiler/source/pizfix \
  --prefix="$root/install" --with-baseruby=/usr/bin/ruby
make -j4 miniruby
./miniruby -v
readelf -l miniruby | grep interpreter
./miniruby -e 'puts File.read("/proc/self/maps").lines.grep(/\.so/).map { |line| line.split.last }.uniq'
