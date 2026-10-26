#!/usr/bin/env bash
set -euo pipefail
root=$(head -1 /work/ta/current-toolchain-dependencies-path.txt)
cd "$root/openssl-build"
recipes=(01-test_symbol_presence 02-test_mem_alloc 02-test_mem_alloc_custom_fns 04-test_bioprint 04-test_param_build 30-test_afalg 90-test_secmem 90-test_shlibload)
for name in "${recipes[@]}"; do
  test ! -e "test/recipes/$name.t"
  tar -xOf /work/openssl-3.6.5.tar.gz "openssl-3.6.5/test/recipes/$name.t" > "test/recipes/$name.t"
done
tar -xOf /work/openssl-3.6.5.tar.gz openssl-3.6.5/test/recipes/70-test_quic_radix.t > test/recipes/70-test_quic_radix.t
patch -p1 < /work/port/dependencies/openssl-bioprint-arguments.patch
make -j4 test/bioprinttest
status=0
timeout -k 10 300 env HARNESS_JOBS=2 make test TESTS='test_symbol_presence test_mem_alloc test_mem_alloc_custom_fns test_bioprint test_param_build test_afalg test_secmem test_shlibload test_quic_radix' > /work/ta/dependency-current-openssl-omitted.log 2>&1 || status=$?
printf '%s\n' "$status" > /work/ta/dependency-current-openssl-omitted.status
tail -45 /work/ta/dependency-current-openssl-omitted.log
exit "$status"
