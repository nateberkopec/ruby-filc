#!/usr/bin/env bash
set -uo pipefail
ruby=$1
prefix=$2
failed=0
for mode in normal raise throw closures cframes receiver forwarding tailcall traced; do
  if timeout -k 5 90 "$ruby" /work/probes/ruby/vm-stack-retirement.rb "$mode" > "$prefix-$mode.log" 2>&1; then status=0; else status=$?; failed=1; fi
  printf '%s\n' "$status" > "$prefix-$mode.status"
  printf '%s: %s\n' "$mode" "$status"
  if test "$status" != 0; then tail -10 "$prefix-$mode.log"; fi
done
exit "$failed"
