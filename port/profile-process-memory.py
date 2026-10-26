import json
from pathlib import Path
import subprocess
import sys
import time

prefix = Path(sys.argv[1])
command = sys.argv[2:]
if not command:
    raise SystemExit('command required')
cgroup = Path('/sys/fs/cgroup')
started = time.monotonic()
known = {}
with prefix.with_suffix('.log').open('w') as output, prefix.with_suffix('.jsonl').open('w') as samples:
    child = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
    while True:
        processes = []
        for directory in Path('/proc').iterdir():
            if not directory.name.isdigit():
                continue
            try:
                stat = (directory / 'stat').read_text()
                fields = stat[stat.rfind(')') + 2:].split()
                if fields[0] == 'Z':
                    continue
                status = dict(line.split(':', 1) for line in (directory / 'status').read_text().splitlines() if ':' in line)
                rss = int(status.get('VmRSS', '0 kB').split()[0])
                if not rss:
                    continue
                identity = directory.name + ':' + fields[19]
                args = (directory / 'cmdline').read_bytes().split(b'\0')
                args = [arg.decode(errors='replace')[:180] for arg in args[:4] if arg]
                for i, arg in enumerate(args):
                    if i and args[i - 1] in ['-e', '-c']:
                        args[i] = '<inline source>'
                if known.get(identity) != args:
                    samples.write(json.dumps({'type': 'process', 't': time.monotonic() - started, 'id': identity, 'args': args}) + '\n')
                    known[identity] = args
                processes.append({'id': identity, 'pid': int(directory.name), 'ppid': int(status['PPid']), 'name': status['Name'].strip(), 'rss_kb': rss, 'anon_kb': int(status.get('RssAnon', '0 kB').split()[0]), 'file_kb': int(status.get('RssFile', '0 kB').split()[0]), 'threads': int(status['Threads'])})
            except (FileNotFoundError, ProcessLookupError):
                continue
        row = {'type': 'sample', 't': time.monotonic() - started, 'current': int((cgroup / 'memory.current').read_text()), 'events': dict((key, int(value)) for key, value in (line.split() for line in (cgroup / 'memory.events').read_text().splitlines())), 'stat': dict((key, int(value)) for key, value in (line.split() for line in (cgroup / 'memory.stat').read_text().splitlines()) if key in ['anon', 'file', 'kernel', 'slab']), 'processes': sorted(processes, key=lambda p: p['rss_kb'], reverse=True)}
        samples.write(json.dumps(row) + '\n')
        samples.flush()
        status = child.poll()
        if status is not None:
            break
        time.sleep(0.25)
prefix.with_suffix('.status').write_text(str(status) + '\n')
raise SystemExit(status)
