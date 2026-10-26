from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
repo = root / 'ruby-4.0.7-glibc'
base = 'ruby-4.0.7-pristine'
paths = subprocess.check_output(['git', 'diff', '--no-ext-diff', '--no-color', '--name-only', base], cwd=repo, text=True).splitlines()
generated = re.compile(r'^(?:enc/trans/[a-z0-9_]+\.c|ext/ripper/ripper\.[cy]|(?:insns_info|optinsn|vm)\.inc|miniprelude\.c|parse\.c|revision\.h)$|\.rbinc$')
paths = [path for path in paths if not generated.search(path)]
(root / 'port/sources.txt').write_text('\n'.join(paths) + '\n')
patch = subprocess.check_output(['git', 'diff', '--no-ext-diff', '--no-color', '--binary', base, '--', *paths], cwd=repo)
(root / 'ruby-4.0.7-filc.patch').write_bytes(patch)
(root / 'example/ruby-4.0.7-filc.patch').write_bytes(patch)
print(subprocess.check_output(['git', 'diff', '--no-ext-diff', '--no-color', '--shortstat', base, '--', *paths], cwd=repo, text=True).strip())
print(f'{len(patch)} bytes, {len(patch.splitlines())} patch lines')
