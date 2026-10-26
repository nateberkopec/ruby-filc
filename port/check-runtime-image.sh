#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
bash "$root/example/smoke.sh"
ruby "$root/port/audit-runtime.rb"
bash "$root/example/regressions.sh"
for mode in enable_race disabled_count overlap atomic_transitions enable_during_overlap fork_count; do
  ruby "$root/treview-gc-state.rb" "$mode"
done
for delay in 0.001 0.005 0.01 0.02 0.04; do
  ruby "$root/treview-disable-retention.rb" "$delay"
done
ruby "$root/treview-weakmap-size.rb"
ruby "$root/tbuffer-remap-contract.rb"
gem install --local --no-document "$root/port/native-gems/nio4r-2.7.5-filc.gem"
gem install --local --no-document "$root/native-gems/cache/puma-8.0.2.gem"
ruby "$root/tnio4r.rb"
ruby "$root/tpuma.rb"
