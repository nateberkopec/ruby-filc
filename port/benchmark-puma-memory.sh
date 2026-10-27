#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")" && pwd)
stock=${1:?Stock Ruby executable required}
filc=${2:?Fil-C Ruby executable required}
output=${3:?Output directory required}
shift 3
mkdir -p "$output"
output=$(cd "$output" && pwd)
for name in stock filc; do
  status=0
  if test "$name" = stock; then
    env -u GEM_HOME -u GEM_PATH -u BUNDLE_APP_CONFIG -u LD_LIBRARY_PATH -u LD_PRELOAD -u RUBYOPT \
      python3 "$root/measure-puma-memory.py" --ruby "$stock" --output "$output/stock.json" "$@" \
      > "$output/stock.log" 2>&1 || status=$?
  else
    python3 "$root/measure-puma-memory.py" --ruby "$filc" --output "$output/filc.json" "$@" \
      > "$output/filc.log" 2>&1 || status=$?
  fi
  printf '%s\n' "$status" > "$output/$name.status"
  if test "$status" != 0; then
    tail -30 "$output/$name.log"
    exit "$status"
  fi
done
status=0
python3 "$root/compare-puma-memory.py" "$output/stock.json" "$output/filc.json" \
  > "$output/comparison.log" 2>&1 || status=$?
printf '%s\n' "$status" > "$output/comparison.status"
while IFS= read -r line; do printf '%s\n' "$line"; done < "$output/comparison.log"
exit "$status"
