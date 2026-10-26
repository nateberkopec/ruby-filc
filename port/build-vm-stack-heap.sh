#!/usr/bin/env bash
set -euo pipefail
prefix=${1:?output prefix required}
build=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
ruby="$build/../install/bin/ruby"
root=$(mktemp -d /compiler/vm-stack-heap-XXXXXX)
printf '%s\n' "$root" > "$prefix-extension-path.txt"
cp /work/probes/c/vm-stack-heap/filc_vm_stack_heap.c "$root/"
cd "$root"
"$ruby" -rmkmf -e '$INCFLAGS << " -I#{ARGV.fetch(0)} -I#{ARGV.fetch(0)}/.ext/include/aarch64-linux"; create_makefile("filc_vm_stack_heap")' "$build"
make -j4
"$ruby" -I"$root" /work/probes/ruby/vm-stack-heap.rb "$prefix"
