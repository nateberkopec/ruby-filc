#!/usr/bin/env bash
set -uo pipefail
failed=0
for kind in normal checked; do
  if test "$kind" = normal; then
    build=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
  else
    build=$(head -1 /work/ta/vm-stack-checked-build-path.txt)
  fi
  cd "$build" || exit
  if timeout -k 15 600 make btest > "/work/ta/vm-stack-revised-$kind-btest.log" 2>&1; then status=0; else status=$?; failed=1; fi
  printf '%s\n' "$status" > "/work/ta/vm-stack-revised-$kind-btest.status"
  printf '%s bootstrap: %s\n' "$kind" "$status"
  tail -8 "/work/ta/vm-stack-revised-$kind-btest.log"
  if bash /work/port/check-current-toolchain-miniruby.sh "$build/miniruby" "/work/ta/vm-stack-revised-$kind-regression" > "/work/ta/vm-stack-revised-$kind-regressions.log" 2>&1; then status=0; else status=$?; failed=1; fi
  printf '%s\n' "$status" > "/work/ta/vm-stack-revised-$kind-regressions.status"
  printf '%s regressions: %s\n' "$kind" "$status"
  tail -12 "/work/ta/vm-stack-revised-$kind-regressions.log"
done
exit "$failed"
