#!/usr/bin/env bash
set -uo pipefail
build=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
export PATH=/compiler/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_LIBDIR=/compiler/source/pizfix/lib/pkgconfig
export LANG=C.UTF-8
unset LD_LIBRARY_PATH
chmod a+rx "$(dirname "$build")"
chmod -R a+rwX "$build"
umask 022
cd "$build" || exit
failed=0
check() {
  local name=$1 limit=$2 status
  shift 2
  cp /sys/fs/cgroup/memory.events "/work/ta/vm-stack-full-$name-memory-before.log"
  if timeout -k 15 "$limit" runuser -u nobody -- "$@" > "/work/ta/vm-stack-full-$name.log" 2>&1; then status=0; else status=$?; failed=1; fi
  printf '%s\n' "$status" > "/work/ta/vm-stack-full-$name.status"
  cp /sys/fs/cgroup/memory.events "/work/ta/vm-stack-full-$name-memory-after.log"
  printf '%s status=%s\n' "$name" "$status"
  tail -8 "/work/ta/vm-stack-full-$name.log"
}
check test-all 1800 make test-all "TEST_EXCLUDES=--excludes-dir=$build/test/.excludes" 'TESTOPTS=-j2 --no-retry --timeout-scale=3'
check spec 900 make test-spec
check capi 600 make test-spec SPECOPTS=spec/ruby/optional/capi
printf '%s\n' "$failed" > /work/ta/vm-stack-full-validation.status
exit "$failed"
