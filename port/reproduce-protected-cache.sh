#!/usr/bin/env bash
set -euo pipefail
build=$(head -1 /work/ta/vmcheck-build-path.txt)
cd "$build"
restore() {
  cp /work/ruby-4.0.7-glibc/vm_insnhelper.c vm_insnhelper.c
  make -j4 miniruby > /work/ta/vmcheck-restore.log 2>&1
}
trap restore EXIT
/usr/bin/ruby - <<'RUBY'
p = 'vm_insnhelper.c'
s = File.read(p)
block = "#ifdef __FILC__\n                    *(VALUE *)&cc_on_stack.klass = vm_cc_klass(cc);\n#endif\n"
raise unless s.include?(block) && s.index(block) == s.rindex(block)
File.write(p, s.sub(block, ''))
RUBY
make -j4 miniruby > /work/ta/vmcheck-protected-before-build.log 2>&1
set +e
timeout -k 5 60 ./miniruby /work/tprotected-callcache.rb > /work/ta/callcache-protected-vmcheck-before.log 2>&1
result=$?
set -e
printf '%s\n' "$result" > /work/ta/callcache-protected-vmcheck-before.status
test "$result" -ne 0
grep -Eq 'cc_check_class|vm_callinfo.h' /work/ta/callcache-protected-vmcheck-before.log
