import hashlib
from pathlib import Path
import subprocess
import tarfile

root = Path('/tmp/ruby-filc')
for name in ['yaml-0.2.5', 'zlib-1.3.2']:
    entries = subprocess.check_output(['git', '-C', str(root / 'source'), 'ls-tree', '-r', 'HEAD', '--', f'projects/{name}'], text=True).splitlines()
    expected = {line.split('\t')[1].removeprefix(f'projects/{name}/'): line.split()[2] for line in entries}
    actual = {}
    with tarfile.open(root / f'{name}.tar.gz') as archive:
        for member in archive.getmembers():
            if member.isfile():
                data = archive.extractfile(member).read()
                actual[member.name.removeprefix(f'{name}/')] = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    changed = [path for path, oid in expected.items() if actual.get(path) != oid]
    print(f'{name}: {len(expected)} tracked paths, {len(changed)} differ or are absent')
    for path in changed:
        print(path, expected[path], actual.get(path))
