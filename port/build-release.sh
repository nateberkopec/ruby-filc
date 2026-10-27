#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
ruby_version=$(awk -F= '$1 == "ARG RUBY_VERSION" { print $2 }' example/Dockerfile)
filc_version=$(awk -F= '$1 == "ARG FILC_VERSION" { print $2 }' example/Dockerfile)
platform=${DOCKER_DEFAULT_PLATFORM:-linux/$(docker version --format '{{.Server.Arch}}')}
case "$platform" in
  linux/arm64|linux/arm64/v8) arch=aarch64 ;;
  linux/amd64) arch=x86_64 ;;
  *) printf 'Unsupported platform: %s\n' "$platform" >&2; exit 1 ;;
esac
archive="example/dist/optfil-${filc_version}-linux-${arch}.tar.xz"
if [ ! -f "$archive" ]; then
  mkdir -p example/dist
  curl --fail --location --retry 3 --max-time 600 "https://github.com/pizlonator/fil-c/releases/download/v${filc_version}/optfil-${filc_version}-linux-${arch}.tar.xz" -o "$archive.partial"
  mv "$archive.partial" "$archive"
fi
docker build --platform "$platform" --build-arg "BUILD_JOBS=${BUILD_JOBS:-4}" --target build \
  -t "ruby-filc-build:$ruby_version" -t "ruby-filc-build:${ruby_version}-filc${filc_version}" example
docker build --platform "$platform" --build-arg "BUILD_JOBS=${BUILD_JOBS:-4}" \
  -t "ruby-filc:$ruby_version" -t "ruby-filc:${ruby_version}-filc${filc_version}" example
