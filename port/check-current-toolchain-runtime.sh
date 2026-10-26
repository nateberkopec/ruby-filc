#!/usr/bin/env bash
set -euo pipefail
build=$(head -1 /work/ta/ruby-cme-current-toolchain-path.txt)
install="$(dirname "$build")/install"
export PATH="$install/bin:/compiler/source/pizfix/bin:/compiler/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.UTF-8
export FILC_CC=/compiler/source/build/bin/clang
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_LIBDIR=/compiler/source/pizfix/lib/pkgconfig
export GEM_HOME
GEM_HOME=$(mktemp -d /compiler/ruby-current-gems-XXXXXX)
export GEM_PATH="$GEM_HOME:$(ruby -rrubygems -e 'print Gem.default_dir')"
printf '%s\n' "$GEM_HOME" > /work/ta/current-toolchain-gems-path.txt
bash /work/example/smoke.sh
bash /work/example/regressions.sh
ruby /work/treview-weakmap-size.rb
ruby /work/tbuffer-remap-contract.rb
gem install --local --no-document /work/port/native-gems/nio4r-2.7.5-filc.gem
gem install --local --no-document /work/native-gems/cache/puma-8.0.2.gem
ruby /work/tnio4r.rb
ruby /work/tpuma.rb
printf '1 + 1\nexit\n' | irb > /work/ta/current-toolchain-irb.log
grep -Eq '^(=>[[:space:]]+)?2$' /work/ta/current-toolchain-irb.log
