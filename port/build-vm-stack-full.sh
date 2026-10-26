#!/usr/bin/env bash
set -euo pipefail
build=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
source=/work/ruby-4.0.7-glibc
cd "$build"
restore() {
  for file in vm.c vm_core.h vm_insnhelper.c; do cp "$source/$file" "$build/$file"; done
}
trap restore EXIT
cp miniruby ../miniruby-vm-stack-revised
for file in vm.c vm_core.h vm_insnhelper.c; do
  git -c safe.directory="$source" -C "$source" show "filc-78e4bb7-recovered:$file" > "$file"
done
rm -f vm.o
if make -j4 miniruby > /work/ta/vm-stack-normal-baseline-build.log 2>&1; then status=0; else status=$?; fi
printf '%s\n' "$status" > /work/ta/vm-stack-normal-baseline-build.status
if test "$status" != 0; then exit "$status"; fi
cp miniruby ../miniruby-vm-stack-baseline
restore
rm -f vm.o
if make -j4 && make install; then status=0; else status=$?; fi
printf '%s\n' "$status" > /work/ta/vm-stack-full-build.status
exit "$status"
