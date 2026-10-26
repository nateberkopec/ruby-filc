#!/usr/bin/env bash
set -uo pipefail
cd /work/ruby-4.0.7-glibc
umask 022
checked=$(head -1 /work/ta/vmcheck-build-path.txt)
failed=0
run_check() {
  local name=$1 status
  shift
  if "$@" > "/work/ta/$name.log" 2>&1; then status=0; else status=$?; failed=1; fi
  printf '%s\n' "$status" > "/work/ta/$name.status"
  printf '%s: %s\n' "$name" "$status"
  if test "$status" != 0; then tail -12 "/work/ta/$name.log"; fi
}
for variant in stock filc vmcheck; do
  case "$variant" in
    stock) ruby=/work/ruby-4.0.7-stock/miniruby ;;
    filc) ruby=/work/ruby-4.0.7-glibc/miniruby ;;
    vmcheck) ruby=$checked/miniruby ;;
  esac
  for kind in attr struct; do
    for operation in read write; do
      for dispatch in direct public_send; do
        for mutation in remove replace; do
          run_check "cme-final-trace-$variant-$kind-$operation-$dispatch-$mutation" timeout -k 5 90 "$ruby" /work/tcallcache-cme-trace.rb "$kind" "$operation" "$dispatch" "$mutation"
        done
      done
    done
  done
  for shape in simple optional keyword keyword_default complex forwarding tailcall arity; do
    run_check "cme-final-warning-$variant-$shape" timeout -k 5 90 "$ruby" /work/tcallcache-cme-warning.rb "$shape"
  done
  for mode in baseline dispatch; do
    run_check "cme-final-lifetime-$variant-$mode" timeout -k 5 90 "$ruby" /work/tcallcache-cme-lifetime.rb "$mode"
  done
  for mode in keep replace release; do
    for count in 1 8; do
      run_check "cme-final-isolate-$variant-$mode-$count" timeout -k 5 90 "$ruby" /work/tcallcache-cme-isolate.rb "$mode" "$count"
    done
  done
  run_check "cme-final-invalidation-$variant" timeout -k 5 120 "$ruby" /work/tcallcache-cme-invalidation.rb
  run_check "cme-final-protected-$variant" timeout -k 5 120 "$ruby" /work/tprotected-callcache.rb
done
run_check btest-cme-reentrancy timeout -k 15 600 make btest
run_check btest-cme-reentrancy-vmcheck timeout -k 15 600 make -C "$checked" btest
paths=()
for file in method class module struct refinement optimization keyword settracefunc alias iterator super proc; do
  paths+=("/work/ruby-4.0.7-glibc/test/ruby/test_$file.rb")
done
run_check cme-reentrancy-regressions timeout -k 15 1200 runuser -u nobody -- make test-all TEST_EXCLUDES=--excludes-dir=/work/ruby-4.0.7-glibc/test/.excludes "TESTOPTS=-j2 --no-retry --timeout-scale=3 ${paths[*]}"
run_check cme-reentrancy-spec timeout -k 15 600 runuser -u nobody -- make test-spec
run_check cme-reentrancy-capi timeout -k 15 300 runuser -u nobody -- make test-spec SPECOPTS=spec/ruby/optional/capi
exit "$failed"
