#!/usr/bin/env bash
set -u
revision=${1:?revision required}
cd /tmp/build/ruby-4.0.7 || exit 1
chmod -R a+rwX . || exit 1
umask 022
cp /sys/fs/cgroup/memory.events "/logs/image-memory-events-$revision-before.log" || exit 1
result=0
run_suite() {
    local name=$1 seconds=$2
    shift 2
    timeout -k 15 "$seconds" runuser -u nobody -- "$@" > "/logs/image-$name-$revision.log" 2>&1
    local status=$?
    printf '%s\n' "$status" > "/logs/image-$name-$revision.status"
    if [[ $status -ne 0 ]]; then result=$status; fi
}
run_suite btest 600 make btest
run_suite test-all 1500 make test-all TEST_EXCLUDES=--excludes-dir=/tmp/build/ruby-4.0.7/test/.excludes 'TESTOPTS=-j2 --no-retry --timeout-scale=3'
run_suite spec 600 make test-spec
cp /sys/fs/cgroup/memory.events "/logs/image-memory-events-$revision-after.log" || exit 1
exit "$result"
