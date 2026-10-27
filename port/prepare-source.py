import argparse
import hashlib
from pathlib import Path
import subprocess
import tarfile
import tempfile
import urllib.request

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description='Create a new Ruby 4.0.9 source worktree from the verified release and port patches.')
parser.add_argument('--archive', type=Path)
parser.add_argument('--destination', type=Path, default=root / 'ruby-4.0.9-glibc')
parser.add_argument('--candidate', action='store_true', help='Also apply the reviewed VM-stack candidate; full-suite validation is incomplete.')
args = parser.parse_args()
destination = args.destination.resolve()
if destination.exists():
    parser.error(f'refusing to overwrite {destination}')
(root / 'tmp').mkdir(exist_ok=True)
archive = args.archive or root / 'tmp/ruby-4.0.9.tar.xz'
if not archive.exists():
    urllib.request.urlretrieve('https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.9.tar.xz', archive)
expected = 'a8057adb39f51ad6dc3106237504c93dd792bb515837b4fe7817ae21ed7e51f4'
if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
    raise SystemExit(f'Ruby archive checksum mismatch: {archive}')
with tempfile.TemporaryDirectory(dir=root / 'tmp') as scratch:
    with tarfile.open(archive) as bundle:
        bundle.extractall(scratch, filter='data')
    destination.parent.mkdir(parents=True, exist_ok=True)
    (Path(scratch) / 'ruby-4.0.9').rename(destination)


def git(*arguments):
    subprocess.run(['git', '-C', str(destination), *arguments], check=True)


git('init', '--quiet', '-b', 'main')
git('add', '-f', '.')
git('commit', '--quiet', '--no-gpg-sign', '-m', 'Import verified Ruby 4.0.9 release sources')
git('-c', 'tag.gpgSign=false', 'tag', 'ruby-4.0.9-pristine')
git('apply', '--check', str(root / 'ruby-4.0.9-filc.patch'))
git('apply', str(root / 'ruby-4.0.9-filc.patch'))
git('add', '-A')
git('commit', '--quiet', '--no-gpg-sign', '-m', 'Apply Fil-C baseline rebased onto Ruby 4.0.9')
git('-c', 'tag.gpgSign=false', 'tag', 'filc-ruby-4.0.9-baseline')
if args.candidate:
    git('switch', '-c', 'vm-stack-retirement')
    git('apply', '--check', str(root / 'port/vm-stack-clear-ruby-4.0.9.patch'))
    git('apply', str(root / 'port/vm-stack-clear-ruby-4.0.9.patch'))
    git('add', 'vm.c', 'vm_core.h', 'vm_insnhelper.c')
    git('commit', '--quiet', '--no-gpg-sign', '-m', 'Apply reviewed VM-stack retirement candidate; full validation pending')
print(destination)
