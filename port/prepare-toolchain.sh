#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git cmake ninja-build clang lld patchelf python3 gawk texinfo gettext libtool automake libcurl4-openssl-dev libssl-dev zlib1g-dev
mkdir -p /compiler/prerequisites
cd /compiler/prerequisites
curl -fLsS https://ftp.gnu.org/gnu/autoconf/autoconf-2.72.tar.xz -o autoconf-2.72.tar.xz
sha256sum autoconf-2.72.tar.xz
tar -xf autoconf-2.72.tar.xz
(cd autoconf-2.72 && ./configure --prefix=/compiler/tools && make -j4 && make install)
mkdir -p /compiler/source
cd /compiler/source
git init
git remote add origin https://github.com/pizlonator/fil-c.git
git config remote.origin.promisor true
git config remote.origin.partialclonefilter blob:none
git config gc.auto 0
git config maintenance.auto false
git sparse-checkout init --no-cone
git sparse-checkout set --no-cone '/README.md'
git fetch --depth=1 --filter=blob:none origin 9d1ed206e0ccfc1ec114471386befeba643a5f86
git checkout --detach FETCH_HEAD
python3 /work/port/populate-toolchain.py
git log -1 --oneline
test -z "$(git status --porcelain --untracked-files=no)"
