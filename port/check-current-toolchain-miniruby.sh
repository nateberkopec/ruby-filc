#!/usr/bin/env bash
set -uo pipefail
build=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
ruby=${1:-$build/miniruby}
prefix=${2:-/work/ta/current-toolchain}
failed=0
check() {
  local name=$1 status
  shift
  if timeout -k 5 150 "$ruby" "$@" > "$prefix-$name.log" 2>&1; then status=0; else status=$?; failed=1; fi
  printf '%s\n' "$status" > "$prefix-$name.status"
  printf '%s: %s\n' "$name" "$status"
  if test "$status" != 0; then tail -15 "$prefix-$name.log"; fi
}
for mode in baseline dispatch; do
  check "cme-lifetime-$mode" /work/tcallcache-cme-lifetime.rb "$mode"
  check "class-lifetime-$mode" /work/tcallcache-lifetime.rb "$mode"
done
for mode in keep replace release; do
  for count in 1 8; do check "cme-isolate-$mode-$count" /work/tcallcache-cme-isolate.rb "$mode" "$count"; done
done
for kind in attr struct; do
  for operation in read write; do
    for dispatch in direct public_send; do
      for mutation in remove replace; do
        check "cme-trace-$kind-$operation-$dispatch-$mutation" /work/tcallcache-cme-trace.rb "$kind" "$operation" "$dispatch" "$mutation"
      done
    done
  done
done
for shape in simple optional keyword keyword_default complex forwarding tailcall arity; do
  check "cme-warning-$shape" /work/tcallcache-cme-warning.rb "$shape"
done
check cme-invalidation /work/tcallcache-cme-invalidation.rb
check protected /work/tprotected-callcache.rb
check metaclass /work/tmetaclass-publication.rb
check subclasses /work/tsubclasses-concurrent-gc.rb
for mode in enable_race disabled_count overlap atomic_transitions enable_during_overlap fork_count; do
  check "gc-$mode" /work/treview-gc-state.rb "$mode"
done
for delay in 0.001 0.005 0.01 0.02 0.04; do
  check "disable-retention-$delay" /work/treview-disable-retention.rb "$delay"
done
check buffer-contract /work/tbuffer-remap-contract.rb
exit "$failed"
