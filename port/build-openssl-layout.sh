#!/usr/bin/env bash
# Build-only experiment. Never installs into the compiler/runtime prefix.
set -euo pipefail
unset CPPFLAGS CFLAGS CXXFLAGS LDFLAGS LIBS LD_LIBRARY_PATH OPENSSL_CONF OPENSSL_MODULES OPENSSL_ENGINES
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
archive=$(realpath "${1:?OpenSSL 3.6.5 archive required}")
descriptor=$(realpath "${2:?Fil-C 0.687 openssl.projeny required}")
build=$(realpath -m "${3:?new build directory required}")
prefix=${FILC_PREFIX:-/opt/fil}
printf '%s  %s\n' a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98 "$archive" \
    828192c156d7673ac1edecbb98a6991a1c7b2c244e40bf5717f3576a9742c732 "$descriptor" | sha256sum -c -
mkdir "$build"
tar -xzf "$archive" -C "$build" --strip-components=1
cd "$build"
patch -p2 < "$descriptor"
# Restore omitted upstream recipes instead of claiming the port's subset is full.
for name in 01-test_symbol_presence 02-test_mem_alloc 02-test_mem_alloc_custom_fns \
    04-test_bioprint 04-test_param_build 30-test_afalg 90-test_secmem 90-test_shlibload; do
    test ! -e "test/recipes/$name.t"
    tar -xOf "$archive" "openssl-3.6.5/test/recipes/$name.t" > "test/recipes/$name.t"
done
tar -xOf "$archive" openssl-3.6.5/test/recipes/70-test_quic_radix.t > test/recipes/70-test_quic_radix.t
patch -p1 < "$root/port/dependencies/openssl-bioprint-arguments.patch"
# Preserve the released port's checked assembly bridges and optimization level.
export CC="$prefix/bin/filcc -yolo-assembler" CFLAGS='-Wall -O3 -g0'
ulimit -c 0
./Configure linux-x86_64 zlib-dynamic --prefix="$prefix" --openssldir=/etc/ssl --libdir=lib
make -j"${BUILD_JOBS:-8}"
mkdir -p artifacts/plain artifacts/relr
cp libcrypto.so.3 libssl.so.3 artifacts/plain/
# Relink identical objects; GNU ld must add the real libc ABI requirement.
test -f crypto/libcrypto-shlib-cversion.o
make -W crypto/libcrypto-shlib-cversion.o LDFLAGS='-Wl,-z,pack-relative-relocs' libcrypto.so.3 libssl.so.3
for library in libcrypto.so.3 libssl.so.3; do
    readelf -d "$library" | grep '(RELR)'
    readelf -V "$library" | grep GLIBC_ABI_DT_RELR
done
cp libcrypto.so.3 libssl.so.3 artifacts/relr/
for variant in plain relr; do
    ln -s libcrypto.so.3 "artifacts/$variant/libcrypto.so"
    ln -s libssl.so.3 "artifacts/$variant/libssl.so"
done
env LD_LIBRARY_PATH="$build" apps/openssl version -a
sha256sum artifacts/{plain,relr}/lib{crypto,ssl}.so.3
# Known upstream-port limitations remain visible as a nonzero result.
env HARNESS_JOBS="${TEST_JOBS:-4}" make test
