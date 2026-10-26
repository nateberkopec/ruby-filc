#!/usr/bin/env bash
set -u
root=$(head -1 /work/ta/current-toolchain-dependencies-path.txt)
cd "$root/openssl-build" || exit 1
result=0
for name in mem_alloc_test mem_alloc_custom_fns_test param_build_test secmemtest bioprinttest; do
  timeout -k 5 30 ./util/wrap.pl "./test/$name" > "/work/ta/openssl-current-$name.log" 2>&1
  status=$?
  printf '%s\n' "$status" > "/work/ta/openssl-current-$name.status"
  printf '%s: %s\n' "$name" "$status"
  grep -E -m4 'filc safety error|Cannot do|error:|At ' "/work/ta/openssl-current-$name.log"
  if [[ $status -ne 0 ]]; then result=$status; fi
 done
exit "$result"
