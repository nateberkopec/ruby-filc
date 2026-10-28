#!/usr/bin/env bash
# Compare user-space instructions and cycles for fixed interpreter kernels.
# Usage: measure-interpreter-overhead.sh STOCK_RUBY FILC_RUBY [FILC_LIBRARY_PATH]
# Requires perf with access to user-space hardware counters. Startup ("empty")
# is subtracted from every case. Counters include every thread, so Fil-C's
# concurrent collector work is counted; nothing forces or disables collection.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
stock=${1:?stock ruby required}
filc=${2:?Fil-C ruby required}
filc_libs=${3:-}
probe="$root/probes/ruby/interpreter-overhead.rb"
cpu=${MEASURE_CPU:-2}
cases=(empty while fib attr array-alloc string-alloc hash-lookup)

count() {
    local ruby=$1 libs=$2 name=$3 environment=(env -u LD_LIBRARY_PATH -u RUBYLIB)
    if [ -n "$libs" ]; then environment+=(LD_LIBRARY_PATH="$libs"); fi
    "${environment[@]}" taskset -c "$cpu" perf stat -x, -e instructions:u,cycles:u "$ruby" "$probe" "$name" 2>&1 >/dev/null |
        awk -F, '$3 ~ /^instructions/ { i = $1 } $3 ~ /^cycles/ { c = $1 } END { print i, c }'
}

declare -A instructions cycles
for runtime in stock filc; do
    for name in "${cases[@]}"; do
        if [ "$runtime" = stock ]; then
            read -r i c < <(count "$stock" '' "$name")
        else
            read -r i c < <(count "$filc" "$filc_libs" "$name")
        fi
        instructions[$runtime,$name]=$i
        cycles[$runtime,$name]=$c
    done
done

printf '%-13s %14s %14s %8s %14s %14s %8s\n' case stock_instr filc_instr ratio stock_cycles filc_cycles ratio
for name in "${cases[@]}"; do
    if [ "$name" = empty ]; then
        si=${instructions[stock,empty]} fi_=${instructions[filc,empty]}
        sc=${cycles[stock,empty]} fc=${cycles[filc,empty]}
    else
        si=$((instructions[stock,$name] - instructions[stock,empty]))
        fi_=$((instructions[filc,$name] - instructions[filc,empty]))
        sc=$((cycles[stock,$name] - cycles[stock,empty]))
        fc=$((cycles[filc,$name] - cycles[filc,empty]))
    fi
    awk -v n="$name" -v si="$si" -v fi="$fi_" -v sc="$sc" -v fc="$fc" \
        'BEGIN { printf "%-13s %14d %14d %8.2f %14d %14d %8.2f\n", n, si, fi, fi / si, sc, fc, fc / sc }'
done
