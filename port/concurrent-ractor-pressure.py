import os
from pathlib import Path
import subprocess
import sys

build = Path('/work/ta/ruby-cme-current-toolchain-path.txt').read_text().strip()
ruby = str(Path(build).parent / 'install/bin/ruby')
prefix = sys.argv[1]
count = int(sys.argv[2]) if len(sys.argv) > 2 else 2
env = dict(os.environ)
children = []
for index in range(count):
    log = Path(f'{prefix}-{index + 1}.log').open('w')
    child = subprocess.Popen([ruby, '/work/trport.rb', '10'], stdout=log, stderr=subprocess.STDOUT, env=env)
    children.append((child, log))
result = 0
for index, (child, log) in enumerate(children, 1):
    status = child.wait()
    log.close()
    Path(f'{prefix}-{index}.status').write_text(str(status) + '\n')
    print(f'child {index} pid={child.pid} status={status}', flush=True)
    if status:
        result = 1
raise SystemExit(result)
