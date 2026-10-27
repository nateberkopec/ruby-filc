import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
(root / 'tmp').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='version-lint-system-', dir=root / 'tmp') as scratch:
    work = Path(scratch)
    (work / 'port').mkdir()
    (work / 'example').mkdir()
    script = work / 'port/check-latest-version.py'
    shutil.copyfile(root / 'port/check-latest-version.py', script)
    original = (root / 'example/Dockerfile').read_text()
    for target, pin in [('ruby', 'RUBY_VERSION'), ('fil-c', 'FILC_VERSION')]:
        cases = [
            ('stale pin', '\n'.join(f'ARG {pin}=0.0.0' if line.startswith(f'ARG {pin}=') else line for line in original.splitlines()), {}, 1),
            ('duplicate pin', original + f'\nARG {pin}=0.0.0\n', {}, 2),
            ('network failure', original, {'HTTPS_PROXY': 'http://127.0.0.1:1', 'https_proxy': 'http://127.0.0.1:1', 'NO_PROXY': '', 'no_proxy': ''}, 2),
        ]
        for name, dockerfile, overrides, expected in cases:
            (work / 'example/Dockerfile').write_text(dockerfile)
            result = subprocess.run([sys.executable, '-I', str(script), target], capture_output=True, text=True, env=os.environ | overrides, timeout=30)
            if result.returncode != expected or result.stdout:
                raise SystemExit(f'{target} {name}: expected exit {expected} with no success output, got {result.returncode}\n{result.stdout}{result.stderr}')
            print(f'{target}: {name} rejected with exit {expected}')
