import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import http.client
import json
import os
from pathlib import Path
import platform
import shutil
import socket
import statistics
import subprocess
import threading
import time

parser = argparse.ArgumentParser(description='Measure a separate Puma server process under a checked HTTP workload.')
parser.add_argument('--ruby', default='ruby')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--rounds', type=int, default=10)
parser.add_argument('--warmup-rounds', type=int, default=5)
parser.add_argument('--requests', type=int, default=1000)
parser.add_argument('--clients', type=int, default=5)
parser.add_argument('--idle', type=float, default=2)
args = parser.parse_args()
if args.rounds < 6 or args.warmup_rounds < 1 or args.requests < args.clients or args.clients < 1 or args.idle <= 0:
    parser.error('require rounds >= 6, warmup-rounds >= 1, requests >= clients >= 1, idle > 0')
root = Path(__file__).resolve().parents[1]
args.output.parent.mkdir(parents=True, exist_ok=True)
with socket.socket() as listener:
    listener.bind(('127.0.0.1', 0))
    port = listener.getsockname()[1]

items = [{'sku': f'item-{i}', 'price': i + 1, 'quantity': 3} for i in range(50)]
note = 'order details ' * 256
expected_items = [{'sku': item['sku'], 'total': item['price'] * 3} for item in items]
digest = hashlib.sha256(note.encode()).hexdigest()
samples = []
monitor_errors = []
phase = 'startup'
stop = threading.Event()
started = time.monotonic()


def request(client, count, batch):
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=60)
    try:
        for index in range(count):
            identity = f'{batch}-{client}-{index}'
            body = json.dumps({'id': identity, 'items': items, 'note': note})
            connection.request('POST', '/orders', body, {'Content-Type': 'application/json'})
            response = connection.getresponse()
            result = json.loads(response.read())
            expected = {'id': identity, 'items': expected_items, 'total': 3825, 'digest': digest}
            if response.status != 200 or result != expected:
                raise RuntimeError(f'incorrect response: {response.status} {result}')
    finally:
        connection.close()


def batch(name):
    with ThreadPoolExecutor(max_workers=args.clients) as pool:
        jobs = [pool.submit(request, client, args.requests // args.clients + (client < args.requests % args.clients), name)
                for client in range(args.clients)]
        for job in jobs:
            job.result()


def sample(pid):
    values = {}
    for line in Path(f'/proc/{pid}/smaps_rollup').read_text().splitlines()[1:]:
        key, value = line.split(':', 1)
        if key in ('Rss', 'Pss', 'Private_Clean', 'Private_Dirty', 'Anonymous', 'Swap'):
            values[key.lower() + '_kb'] = int(value.split()[0])
    values['uss_kb'] = values['private_clean_kb'] + values['private_dirty_kb']
    values.update(t=time.monotonic() - started, phase=phase)
    return values


def monitor(pid):
    try:
        while not stop.is_set():
            samples.append(sample(pid))
            stop.wait(0.1)
    except OSError as error:
        monitor_errors.append(error)
        stop.set()


ruby = shutil.which(args.ruby)
if ruby is None:
    raise SystemExit(f'Ruby executable not found: {args.ruby}')
identity = {
    'ruby_path': ruby,
    'ruby_sha256': hashlib.sha256(Path(ruby).read_bytes()).hexdigest(),
    'platform': platform.platform(),
    'cpus': sorted(os.sched_getaffinity(0)),
    'environment': {key: value for key, value in os.environ.items()
                    if key.startswith(('RUBY_GC_', 'RUBY_YJIT_', 'RUBY_ZJIT_', 'FUGC_'))
                    or key in ('RUBYOPT', 'LD_LIBRARY_PATH', 'MALLOC_ARENA_MAX')},
}
with args.output.with_suffix('.server.log').open('w') as output:
    server = subprocess.Popen([args.ruby, str(root / 'probes/ruby/puma-memory-app.rb'), str(port)],
                              stdout=output, stderr=subprocess.STDOUT,
                              env={**os.environ, 'PUMA_THREADS': str(args.clients)})
    watcher = None
    try:
        deadline = time.monotonic() + 60
        while True:
            if server.poll() is not None:
                raise RuntimeError(f'Puma exited during startup: {server.returncode}')
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=1)
            try:
                connection.request('GET', '/health')
                response = connection.getresponse()
                if response.status != 200 or response.read() != b'ready':
                    raise RuntimeError('invalid health response')
                break
            except (ConnectionRefusedError, TimeoutError):
                if time.monotonic() >= deadline:
                    raise RuntimeError('Puma startup timed out')
                time.sleep(0.1)
            finally:
                connection.close()
        mappings = Path(f'/proc/{server.pid}/maps').read_text().splitlines()
        libraries = sorted({line.split()[-1] for line in mappings if '/libruby.so' in line})
        identity['libruby_sha256'] = {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in libraries}
        watcher = threading.Thread(target=monitor, args=(server.pid,))
        watcher.start()
        phase = 'warmup'
        for index in range(args.warmup_rounds):
            batch(f'warmup-{index}')
        for index in range(args.rounds):
            phase = f'load-{index}'
            batch(index)
            phase = f'idle-{index}'
            time.sleep(args.idle)
        args.output.with_suffix('.smaps').write_text(Path(f'/proc/{server.pid}/smaps').read_text())
        phase = 'post-gc'
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=60)
        try:
            connection.request('GET', '/gc')
            response = connection.getresponse()
            gc = json.loads(response.read())
            if response.status != 200:
                raise RuntimeError(f'GC request failed: {response.status}')
        finally:
            connection.close()
        time.sleep(max(args.idle, 1))
        if server.poll() is not None:
            raise RuntimeError(f'Puma exited during workload: {server.returncode}')
    finally:
        stop.set()
        if watcher is not None:
            watcher.join()
        server.terminate()
        try:
            status = server.wait(timeout=15)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
            raise RuntimeError('Puma did not shut down within 15 seconds')
        args.output.with_suffix('.samples.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in samples))
    if status != 0:
        raise RuntimeError(f'Puma shutdown failed: {status}')
    if monitor_errors:
        raise RuntimeError('memory sampler failed') from monitor_errors[0]

identity['server'] = next(json.loads(line) for line in args.output.with_suffix('.server.log').read_text().splitlines()
                          if line.startswith('{"ruby":'))
steady = [row for row in samples if row['phase'].startswith(('load-', 'idle-'))]
metrics = {}
for key in ('rss_kb', 'pss_kb', 'uss_kb'):
    idles = [statistics.median(row[key] for row in samples if row['phase'] == f'idle-{i}') for i in range(args.rounds)]
    metrics[key] = {
        'median': statistics.median(row[key] for row in steady),
        'peak': max(row[key] for row in steady),
        'idle_rounds': idles,
        'late_growth': statistics.median(idles[-3:]) - statistics.median(idles[:3]),
        'post_gc': statistics.median(row[key] for row in samples if row['phase'] == 'post-gc'),
    }
result = {'config': {**vars(args), 'output': str(args.output)}, 'identity': identity,
          'metrics': metrics, 'gc': gc, 'requests_checked': args.requests * (args.rounds + args.warmup_rounds),
          'elapsed': time.monotonic() - started}
args.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
