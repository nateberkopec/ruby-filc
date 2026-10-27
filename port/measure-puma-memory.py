import argparse
from array import array
from concurrent.futures import ProcessPoolExecutor
import hashlib
import http.client
import json
import math
import multiprocessing
import os
from pathlib import Path
import platform
import shutil
import socket
import statistics
import subprocess
import threading
import time


def cpu_set(value):
    cpus = set()
    try:
        for part in value.split(','):
            bounds = [int(item) for item in part.split('-')]
            if len(bounds) == 1:
                bounds.append(bounds[0])
            if len(bounds) != 2 or bounds[0] < 0 or bounds[1] < bounds[0]:
                raise ValueError(value)
            cpus.update(range(bounds[0], bounds[1] + 1))
    except ValueError as error:
        raise argparse.ArgumentTypeError('use CPU numbers or ranges, such as 0-3 or 0,2') from error
    return sorted(cpus)


def request(port, client, count, batch):
    items = [{'sku': f'item-{i}', 'price': i + 1, 'quantity': 3} for i in range(50)]
    note = 'order details ' * 256
    expected_items = [{'sku': item['sku'], 'total': item['price'] * 3} for item in items]
    digest = hashlib.sha256(note.encode()).hexdigest()
    latencies = []
    cpu_started = time.process_time()
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=60)
    try:
        for index in range(count):
            identity = f'{batch}-{client}-{index}'
            body = json.dumps({'id': identity, 'items': items, 'note': note})
            started = time.perf_counter_ns()
            connection.request('POST', '/orders', body, {'Content-Type': 'application/json'})
            response = connection.getresponse()
            payload = response.read()
            elapsed = time.perf_counter_ns() - started
            result = json.loads(payload)
            expected = {'id': identity, 'items': expected_items, 'total': 3825, 'digest': digest}
            if response.status != 200 or result != expected:
                raise RuntimeError(f'incorrect response: {response.status} {result}')
            latencies.append(elapsed)
    finally:
        connection.close()
    return {'latency_ns': latencies, 'cpu_seconds': time.process_time() - cpu_started}


def cpu_seconds(pid):
    fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / os.sysconf('SC_CLK_TCK')


def batch(pool, port, name, clients, requests, pid):
    server_cpu = cpu_seconds(pid)
    started = time.perf_counter()
    jobs = [pool.submit(request, port, client, requests // clients + (client < requests % clients), name)
            for client in range(clients)]
    results = [job.result() for job in jobs]
    elapsed = time.perf_counter() - started
    return {'batch': name, 'elapsed_seconds': elapsed,
            'server_cpu_seconds': cpu_seconds(pid) - server_cpu,
            'client_cpu_seconds': sum(result['cpu_seconds'] for result in results),
            'latency_ns': [value for result in results for value in result['latency_ns']]}


def sample(pid, started, phase):
    values = {}
    for line in Path(f'/proc/{pid}/smaps_rollup').read_text().splitlines()[1:]:
        key, value = line.split(':', 1)
        if key in ('Rss', 'Pss', 'Private_Clean', 'Private_Dirty', 'Anonymous', 'Swap'):
            values[key.lower() + '_kb'] = int(value.split()[0])
    values['uss_kb'] = values['private_clean_kb'] + values['private_dirty_kb']
    values.update(t=time.monotonic() - started, phase=phase)
    return values


def main():
    parser = argparse.ArgumentParser(description='Measure Puma memory, checked load throughput and HTTP latency.')
    parser.add_argument('--ruby', default='ruby')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=10)
    parser.add_argument('--warmup-rounds', type=int, default=5)
    parser.add_argument('--requests', type=int, default=1000)
    parser.add_argument('--clients', type=int, default=5)
    parser.add_argument('--idle', type=float, default=2)
    parser.add_argument('--server-cpus', type=cpu_set)
    parser.add_argument('--client-cpus', type=cpu_set)
    args = parser.parse_args()
    if args.rounds < 6 or args.warmup_rounds < 1 or args.requests < args.clients or args.clients < 1 or args.idle <= 0:
        parser.error('require rounds >= 6, warmup-rounds >= 1, requests >= clients >= 1, idle > 0')
    allowed = set(os.sched_getaffinity(0))
    if (args.server_cpus is None) != (args.client_cpus is None):
        parser.error('supply both --server-cpus and --client-cpus')
    if args.server_cpus is not None:
        server_cpus, client_cpus = set(args.server_cpus), set(args.client_cpus)
        if not server_cpus <= allowed or not client_cpus <= allowed:
            parser.error('requested CPUs are outside the available CPU affinity')
        if server_cpus & client_cpus:
            parser.error('server and client CPU sets must be disjoint')
    else:
        server_cpus = client_cpus = allowed
    os.sched_setaffinity(0, client_cpus)
    root = Path(__file__).resolve().parents[1]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    ruby = shutil.which(args.ruby)
    if ruby is None:
        raise SystemExit(f'Ruby executable not found: {args.ruby}')
    identity = {
        'ruby_path': ruby,
        'ruby_sha256': hashlib.sha256(Path(ruby).read_bytes()).hexdigest(),
        'platform': platform.platform(),
        'cpus': sorted(server_cpus),
        'client_cpus': sorted(client_cpus),
        'load_generator': 'python-process-pool-v1',
        'driver_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'workload_sha256': hashlib.sha256((root / 'probes/ruby/puma-memory-app.rb').read_bytes()).hexdigest(),
        'limits': {name: Path('/sys/fs/cgroup', name).read_text().strip()
                   for name in ('memory.max', 'memory.high', 'memory.swap.max', 'cpu.max')},
        'python': platform.python_version(),
        'environment': {key: value for key, value in os.environ.items()
                        if key.startswith(('RUBY_GC_', 'RUBY_YJIT_', 'RUBY_ZJIT_', 'FUGC_'))
                        or key in ('RUBYOPT', 'LD_LIBRARY_PATH', 'LD_PRELOAD', 'MALLOC_ARENA_MAX')},
    }
    samples = []
    monitor_errors = []
    phase = 'startup'
    stop = threading.Event()
    started = time.monotonic()
    latencies = array('Q')
    loads = []

    def monitor(pid):
        try:
            while not stop.is_set():
                samples.append(sample(pid, started, phase))
                stop.wait(0.1)
        except OSError as error:
            monitor_errors.append(error)
            stop.set()

    with args.output.with_suffix('.server.log').open('w') as output:
        server = subprocess.Popen([ruby, str(root / 'probes/ruby/puma-memory-app.rb'), str(port)],
                                  stdout=output, stderr=subprocess.STDOUT,
                                  preexec_fn=lambda: os.sched_setaffinity(0, server_cpus),
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
            if set(os.sched_getaffinity(server.pid)) != server_cpus:
                raise RuntimeError('server CPU affinity differs from the requested affinity')
            mappings = Path(f'/proc/{server.pid}/maps').read_text().splitlines()
            libraries = sorted({line.split()[-1] for line in mappings if '/libruby.so' in line})
            identity['libruby_sha256'] = {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in libraries}
            watcher = threading.Thread(target=monitor, args=(server.pid,))
            watcher.start()
            with ProcessPoolExecutor(max_workers=args.clients, mp_context=multiprocessing.get_context('spawn')) as pool:
                phase = 'warmup'
                for index in range(args.warmup_rounds):
                    batch(pool, port, f'warmup-{index}', args.clients, args.requests, server.pid)
                with args.output.with_suffix('.latencies.jsonl').open('w') as latency_output:
                    for index in range(args.rounds):
                        phase = f'load-{index}'
                        load = batch(pool, port, index, args.clients, args.requests, server.pid)
                        phase = f'idle-{index}'
                        latency_output.write(json.dumps(load, separators=(',', ':')) + '\n')
                        latency_output.flush()
                        latencies.extend(load.pop('latency_ns'))
                        loads.append(load)
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
        idles = []
        for index in range(args.rounds):
            values = [row[key] for row in samples if row['phase'] == f'idle-{index}']
            if not values:
                raise RuntimeError(f'No samples for idle-{index}; increase --idle')
            idles.append(statistics.median(values))
        metrics[key] = {
            'median': statistics.median(row[key] for row in steady),
            'peak': max(row[key] for row in steady),
            'idle_rounds': idles,
            'late_growth': statistics.median(idles[-3:]) - statistics.median(idles[:3]),
            'post_gc': statistics.median(row[key] for row in samples if row['phase'] == 'post-gc'),
        }
    if len(latencies) != args.rounds * args.requests:
        raise RuntimeError('latency sample count differs from the checked measured request count')
    ordered = sorted(latencies)
    load_seconds = sum(load['elapsed_seconds'] for load in loads)
    metrics['performance'] = {
        'requests': len(latencies),
        'load_seconds': load_seconds,
        'requests_per_second': len(latencies) / load_seconds,
        'latency_ms': {f'p{percentile}': ordered[math.ceil(len(ordered) * percentile / 100) - 1] / 1_000_000
                       for percentile in (50, 95, 99)},
        'client_cpu_utilization': sum(load['client_cpu_seconds'] for load in loads) / load_seconds / len(client_cpus),
        'max_round_client_cpu_utilization': max(load['client_cpu_seconds'] / load['elapsed_seconds'] / len(client_cpus)
                                                for load in loads),
        'server_cpu_seconds': sum(load['server_cpu_seconds'] for load in loads),
        'rounds': loads,
    }
    result = {'schema_version': 2, 'config': {**vars(args), 'output': str(args.output)}, 'identity': identity,
              'metrics': metrics, 'gc': gc, 'requests_checked': args.requests * (args.rounds + args.warmup_rounds),
              'elapsed': time.monotonic() - started}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
