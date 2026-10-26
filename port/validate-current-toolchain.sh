#!/usr/bin/env bash
set -u
build=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
cd "$build" || exit 1
chmod a+rx "$(dirname "$build")" || exit 1
chmod -R a+rwX "$build" || exit 1
umask 022
export LANG=C.UTF-8
export PATH=/compiler/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
command -v runuser >/dev/null || exit 1
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_LIBDIR=/compiler/source/pizfix/lib/pkgconfig
unset LD_LIBRARY_PATH
result=0
run_suite() {
  local name=$1 seconds=$2 status
  shift 2
  cp /sys/fs/cgroup/memory.events "/work/ta/current-toolchain-$name-memory-before.log" || exit 1
  timeout -k 15 "$seconds" runuser -u nobody -- "$@" > "/work/ta/current-toolchain-$name.log" 2>&1
  status=$?
  printf '%s\n' "$status" > "/work/ta/current-toolchain-$name.status"
  cp /sys/fs/cgroup/memory.events "/work/ta/current-toolchain-$name-memory-after.log" || exit 1
  tail -8 "/work/ta/current-toolchain-$name.log"
  if [[ $status -ne 0 ]]; then result=$status; fi
}
run_suite btest-full 600 make btest
run_suite test-all 1800 make test-all "TEST_EXCLUDES=--excludes-dir=$build/test/.excludes" 'TESTOPTS=-j2 --no-retry --timeout-scale=3'
run_suite spec 900 make test-spec
run_suite capi 600 make test-spec SPECOPTS=spec/ruby/optional/capi
exit "$result"
