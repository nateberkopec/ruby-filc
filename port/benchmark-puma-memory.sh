#!/usr/bin/env bash
set -euo pipefail
filc_overrides=()
if [[ -v LD_LIBRARY_PATH ]]; then filc_overrides+=(--server-library-path "$LD_LIBRARY_PATH"); fi
if [[ -v RUBYLIB ]]; then filc_overrides+=(--server-rubylib "$RUBYLIB"); fi
unset LD_LIBRARY_PATH RUBYLIB
root=$(cd -- "$(dirname -- "$0")" && pwd)
stock=${1:?Stock Ruby executable required}
filc=${2:?Fil-C Ruby executable required}
output=${3:?Output directory required}
shift 3
shared_args=()
while test "$#" -gt 0; do
  case "$1" in
    --server-library-path|--server-rubylib)
      if test "$#" -lt 2; then printf '%s requires a value\n' "$1" >&2; exit 2; fi
      filc_overrides+=("$1" "$2")
      shift 2
      ;;
    --server-library-path=*|--server-rubylib=*) filc_overrides+=("$1"); shift;;
    *) shared_args+=("$1"); shift;;
  esac
done
mkdir -p "$output"
output=$(cd "$output" && pwd)
for name in stock filc; do
  status=0
  if test "$name" = stock; then
    env -u GEM_HOME -u GEM_PATH -u BUNDLE_APP_CONFIG -u LD_LIBRARY_PATH -u LD_PRELOAD -u RUBYOPT \
      python3 "$root/measure-puma-memory.py" --ruby "$stock" --output "$output/stock.json" "${shared_args[@]}" \
      > "$output/stock.log" 2>&1 || status=$?
  else
    python3 "$root/measure-puma-memory.py" --ruby "$filc" --output "$output/filc.json" "${shared_args[@]}" "${filc_overrides[@]}" \
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
