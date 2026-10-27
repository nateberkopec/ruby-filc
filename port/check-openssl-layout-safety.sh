#!/usr/bin/env bash
set -euo pipefail
unset LD_LIBRARY_PATH
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
output=$(realpath -m "${1:?new output directory required}")
shift
test "$#" -gt 0
mkdir "$output"
ulimit -c 0
"${FILC_CC:-/opt/fil/bin/filcc}" -O3 "$root/probes/c/openssl-checked-aes.c" -lcrypto -o "$output/aes"
index=0
for library in "$@"; do
    library=$(realpath -e "$library")
    index=$((index + 1))
    printf '%s\n' "$library" > "$output/$index-library.txt"
    sha256sum "$library/libcrypto.so.3" >> "$output/$index-library.txt"
    env LD_LIBRARY_PATH="$library" "$output/aes" valid > "$output/$index-valid.log" 2>&1
    for mode in key input output rounds alias readonly; do
        status=0
        env LD_LIBRARY_PATH="$library" "$output/aes" "$mode" > "$output/$index-$mode.log" 2>&1 || status=$?
        printf '%s\n' "$status" > "$output/$index-$mode.status"
        test "$status" -eq 133
        grep -q 'filc safety error' "$output/$index-$mode.log"
    done
done
printf '%s library variants: valid AES checks pass; all six invalid calls per variant rejected\n' "$index"
