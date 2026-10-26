#!/usr/bin/env bash
set -euo pipefail
revision=${1:?revision required}
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
container=$(docker run --detach --rm --publish 127.0.0.1::9292 "ruby-filc-app:4.0.7-$revision")
cleanup() {
    local status=$?
    if ! docker logs "$container" > "$root/ta/app-server-$revision.log" 2>&1; then
        printf 'Could not capture application container logs\n' >&2
        status=1
    fi
    if ! docker stop "$container" >/dev/null; then
        printf 'Could not stop application container %s\n' "$container" >&2
        status=1
    fi
    exit "$status"
}
trap cleanup EXIT
endpoint=$(docker port "$container" 9292/tcp)
docker exec "$container" ruby -rsocket -rtimeout -e 'Timeout.timeout(30) { loop { begin; TCPSocket.new("127.0.0.1", 9292).close; break; rescue Errno::ECONNREFUSED; sleep 0.1; end } }'
curl --noproxy '*' --fail --show-error --silent --max-time 5 "http://$endpoint/" > "$root/ta/app-http-$revision.json"
ruby -rjson -e 'response = JSON.parse(File.read(ARGV.fetch(0))); raise response.inspect unless response.fetch("ruby").start_with?("ruby 4.0.7 ") && response.fetch("compiler") == "/opt/fil/bin/filcc"; puts response' "$root/ta/app-http-$revision.json"
printf '1 + 1\nexit\n' | docker run --rm -i "ruby-filc:4.0.7-$revision" > "$root/ta/irb-$revision.log" 2>&1
grep -Eq '^(=>[[:space:]]+)?2$' "$root/ta/irb-$revision.log"
