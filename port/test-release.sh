#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
version=$(awk -F= '$1 == "ARG RUBY_VERSION" { print $2 }' "$root/example/Dockerfile")
docker run --rm --memory=8g --memory-swap=8g --cpuset-cpus=0-3 \
  --mount "type=bind,src=$root,dst=/checks,readonly" "ruby-filc:$version" \
  bash -c 'bash /checks/example/smoke.sh && bash /checks/example/regressions.sh && ruby /checks/probes/ruby/shape-cache-chunks.rb --dump-shapes'
