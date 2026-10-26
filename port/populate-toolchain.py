import os
from pathlib import Path
import subprocess

root = Path('/compiler/source')
os.chdir(root)
dirs = ['llvm', 'clang', 'cmake', 'third-party', 'libpas', 'filc', 'compiler-rt', 'libc', 'libcxx', 'libcxxabi', 'runtimes', 'yolounwind', 'projects/yolo-glibc-2.44', 'projects/user-glibc-2.44', 'projects/projeny', 'projects/minilute', 'projects/sarcasm', 'projects/libxcrypt-4.5.2', 'projects/lute-1.0.0/extern/luau']
excluded = ['llvm/test/', 'clang/test/', 'llvm/unittests/', 'clang/unittests/']
entries = subprocess.check_output(['git', 'ls-tree', '-r', 'HEAD', '--', *dirs]).decode().splitlines()
entries += subprocess.check_output(['git', 'ls-tree', 'HEAD']).decode().splitlines()
objects = set()
for entry in entries:
    metadata, path = entry.split('\t', 1)
    mode, kind, oid = metadata.split()
    if kind == 'blob' and not any(path.startswith(prefix) for prefix in excluded):
        objects.add(oid)
present = set(subprocess.check_output(['git', 'cat-file', '--batch-all-objects', '--unordered', '--batch-check=%(objectname)'], text=True).splitlines())
missing = sorted(objects - present)
print(f'{len(objects)} selected blobs, {len(missing)} missing', flush=True)
for start in range(0, len(missing), 5000):
    batch = missing[start:start + 5000]
    print(f'Fetching {start + 1}..{start + len(batch)} of {len(missing)}', flush=True)
    subprocess.run(['git', '-c', 'gc.auto=0', '-c', 'maintenance.auto=false', 'fetch', '--no-tags', '--no-write-fetch-head', '--recurse-submodules=no', '--filter=blob:none', '--stdin', 'origin'], input='\n'.join(batch) + '\n', text=True, check=True)
patterns = ['/*', '!/*/'] + [f'/{directory}/' for directory in dirs] + [f'!/{directory}' for directory in excluded]
subprocess.run(['git', 'sparse-checkout', 'set', '--no-cone', '--stdin'], input='\n'.join(patterns) + '\n', text=True, check=True)
subprocess.run(['git', 'restore', '--worktree', '--', '.'], check=True)
status = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], text=True)
if status:
    raise RuntimeError(status)
print('Selected source is populated and matches HEAD', flush=True)
