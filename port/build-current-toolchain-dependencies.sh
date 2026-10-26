#!/usr/bin/env bash
set -euo pipefail
root=$(mktemp -d /compiler/ruby-native-deps-XXXXXX)
printf '%s\n' "$root" > /work/ta/current-toolchain-dependencies-path.txt
prefix=/compiler/source/pizfix
export PATH=/compiler/tools/bin:/usr/bin:/bin
export CC=/compiler/source/build/bin/clang
export CXX=/compiler/source/build/bin/clang++
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS LIBS LD_LIBRARY_PATH
command -v runtest
cd /work
sha256sum -c <<'SUMS'
bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16  zlib-1.3.2.tar.gz
c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4  yaml-0.2.5.tar.gz
a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98  openssl-3.6.5.tar.gz
7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4  source/projects/libffi-3.8.0.tar.gz
b7c1bbb325b327c9d0dfdff723ee5a88dd93e17eea497cb45fd62df0d1b0964d  source/projects/libffi.projeny
70b56dd2310e941719ac342b42b2e4cbfbd0dd6c8319cc89afb8851bd20f3f31  source/projects/openssl.projeny
SUMS
cp source/projects/{libffi.projeny,libffi-3.8.0.tar.gz,openssl.projeny} "$root/"
cp openssl-3.6.5.tar.gz "$root/.openssl-3.6.5.tar.gz.snapshot"
test "$(/compiler/source/filc/projeny hash "$root/.openssl-3.6.5.tar.gz.snapshot")" = 1f7fe0f6b2d9c46f70eee94d4e8700cf754623e9764af424e3eb9a9127d77999
tar -xzf /work/zlib-1.3.2.tar.gz -C "$root"
tar -xzf /work/yaml-0.2.5.tar.gz -C "$root"
patch -d "$root/zlib-1.3.2" -p1 < /work/port/dependencies/zlib-1.3.2-filc.patch
test "$(git hash-object "$root/zlib-1.3.2/crc32.c")" = e949ad80f41ac246191c2243f4ffd4358364efed
/compiler/source/filc/projeny extract "$root/libffi.projeny" "$root/libffi-build"
/compiler/source/filc/projeny extract "$root/openssl.projeny" "$root/openssl-build"
run_step() {
  local name=$1
  shift
  local status=0
  "$@" > "/work/ta/dependency-current-$name.log" 2>&1 || status=$?
  printf '%s\n' "$status" > "/work/ta/dependency-current-$name.status"
  tail -8 "/work/ta/dependency-current-$name.log"
  return "$status"
}
cd "$root/zlib-1.3.2"
run_step zlib-configure env CFLAGS='-O3 -g' ./configure --prefix="$prefix"
run_step zlib-build make -j4
run_step zlib-check make check
run_step zlib-install make install
cd "$root/yaml-0.2.5"
run_step yaml-configure ./configure --enable-shared --prefix="$prefix"
run_step yaml-build make -j4
run_step yaml-check make -j4 check
run_step yaml-install make install
cd "$root/libffi-build"
run_step ffi-configure ./configure --prefix="$prefix" --disable-exec-static-tramp
run_step ffi-build make -j4
run_step ffi-check make -j4 check
run_step ffi-install make install
run_step ffi-probe-build "$CC" -O2 -g -o ffitest ffitest.c -lffi -Wno-incompatible-function-pointer-types
run_step ffi-probe ./ffitest
run_step ffi-probe-output diff ffitest.expected /work/ta/dependency-current-ffi-probe.log
cd "$root/openssl-build"
run_step openssl-configure env CC="$CC -g -O2 -yolo-assembler" ./Configure zlib --prefix="$prefix" --libdir=lib
run_step openssl-build make -j4
run_step openssl-check env HARNESS_JOBS=4 make test
run_step openssl-install make -j4 install_sw install_ssldirs
"$prefix/bin/openssl" version -a
"$PKG_CONFIG" --modversion zlib yaml-0.1 libffi openssl
bash /work/port/check-openssl-omitted-tests.sh
