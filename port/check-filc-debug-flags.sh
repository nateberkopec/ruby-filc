#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
output=$(realpath -m "${1:?new output directory required}")
compiler=${FILC_CC:-/opt/fil/bin/filcc}
mkdir "$output"
ulimit -c 0
for flag in ggdb3 g0; do
    "$compiler" -O3 "-$flag" "$root/probes/c/checked-access.c" -o "$output/$flag"
    "$output/$flag" valid > "$output/$flag-valid.log" 2>&1
    printf '%s valid: passed\n' "$flag"
    for scenario in bounds freed readonly call; do
        status=0
        "$output/$flag" "$scenario" > "$output/$flag-$scenario.log" 2>&1 || status=$?
        printf '%s\n' "$status" > "$output/$flag-$scenario.status"
        if [ "$status" -eq 0 ] || ! grep -q 'filc safety error' "$output/$flag-$scenario.log"; then
            printf '%s %s did not report the required safety error (exit %s)\n' "$flag" "$scenario" "$status" >&2
            exit 1
        fi
        printf '%s %s: rejected (exit %s)\n' "$flag" "$scenario" "$status"
    done
done
