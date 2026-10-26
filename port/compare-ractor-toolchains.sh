#!/usr/bin/env bash
set -uo pipefail
current=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
for executable in /usr/bin/time "$current/miniruby" /work/ruby-4.0.7-glibc/miniruby; do
  if ! test -x "$executable"; then
    printf 'Missing executable: %s\n' "$executable" >&2
    exit 127
  fi
done
failed=0
for round in 1 2 3; do
  if test "$round" = 2; then variants=(current release); else variants=(release current); fi
  for variant in "${variants[@]}"; do
    if test "$variant" = current; then ruby=$current/miniruby; else ruby=/work/ruby-4.0.7-glibc/miniruby; fi
    name=ractor-cme-toolchain-$variant-$round
    cp /sys/fs/cgroup/memory.events "/work/ta/$name-memory-before.log"
    if timeout -k 15 300 /usr/bin/time -v "$ruby" /work/trport.rb 10 > "/work/ta/$name.log" 2>&1; then status=0; else status=$?; failed=1; fi
    printf '%s\n' "$status" > "/work/ta/$name.status"
    cp /sys/fs/cgroup/memory.events "/work/ta/$name-memory-after.log"
    printf '%s: %s\n' "$name" "$status"
    tail -24 "/work/ta/$name.log"
  done
done
exit "$failed"
