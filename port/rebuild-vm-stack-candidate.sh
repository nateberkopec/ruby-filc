#!/usr/bin/env bash
set -euo pipefail
for kind in normal checked; do
  if test "$kind" = normal; then
    build=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
  else
    build=$(head -1 /work/ta/vm-stack-checked-build-path.txt)
  fi
  for source in vm.c vm_core.h vm_insnhelper.c; do
    cp "/work/ruby-4.0.7-glibc/$source" "$build/$source"
  done
  cd "$build"
  rm -f vm.o
  if make -j4 miniruby > "/work/ta/vm-stack-revised-$kind-build.log" 2>&1; then status=0; else status=$?; fi
  printf '%s\n' "$status" > "/work/ta/vm-stack-revised-$kind-build.status"
  tail -5 "/work/ta/vm-stack-revised-$kind-build.log"
  if test "$status" != 0; then exit "$status"; fi
  if timeout -k 5 30 ./miniruby -e 0 > "/work/ta/vm-stack-revised-$kind-startup.log" 2>&1; then status=0; else status=$?; fi
  printf '%s\n' "$status" > "/work/ta/vm-stack-revised-$kind-startup.status"
  printf '%s startup: %s\n' "$kind" "$status"
  if test "$status" != 0; then tail -20 "/work/ta/vm-stack-revised-$kind-startup.log"; exit "$status"; fi
done
