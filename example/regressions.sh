#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")" && pwd)
ruby "$root/regressions/callcache-lifetime.rb" baseline
ruby "$root/regressions/callcache-lifetime.rb" dispatch
ruby "$root/regressions/callcache-dump.rb"
for mode in baseline dispatch; do
  ruby "$root/regressions/callcache-cme-lifetime.rb" "$mode"
done
for mode in keep replace release; do
  for count in 1 8; do
    ruby "$root/regressions/callcache-cme-isolate.rb" "$mode" "$count"
  done
done
ruby "$root/regressions/callcache-cme-invalidation.rb"
for kind in attr struct; do
  for operation in read write; do
    for dispatch in direct public_send; do
      for mutation in remove replace; do
        ruby "$root/regressions/callcache-cme-trace.rb" "$kind" "$operation" "$dispatch" "$mutation"
      done
    done
  done
done
for shape in simple optional keyword keyword_default complex forwarding tailcall arity; do
  ruby "$root/regressions/callcache-cme-warning.rb" "$shape"
done
ruby "$root/regressions/protected-callcache.rb"
ruby "$root/regressions/metaclass-publication.rb"
ruby "$root/regressions/subclasses-concurrent-gc.rb"
