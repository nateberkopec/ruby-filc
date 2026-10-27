import argparse
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser(description='Require Puma memory/latency within 105% and throughput at least 95% of stock.')
parser.add_argument('stock', type=Path)
parser.add_argument('filc', type=Path)
args = parser.parse_args()
stock = json.loads(args.stock.read_text())
filc = json.loads(args.filc.read_text())
for name, result in (('stock', stock), ('Fil-C', filc)):
    if result.get('schema_version') != 2 or 'performance' not in result['metrics']:
        raise SystemExit(f'{name}: missing current performance evidence; rerun both runtimes with the current driver')
    identity = result['identity']
    if not identity['cpus'] or not identity['client_cpus'] or set(identity['cpus']) & set(identity['client_cpus']):
        raise SystemExit(f'{name}: performance acceptance requires disjoint server/client CPU sets')
    performance = result['metrics']['performance']
    expected = result['config']['rounds'] * result['config']['requests']
    if performance['requests'] != expected or len(performance['rounds']) != result['config']['rounds']:
        raise SystemExit(f'{name}: incomplete performance samples')
    values = [performance['requests_per_second'], performance['load_seconds'], *performance['latency_ms'].values()]
    if any(not math.isfinite(value) or value <= 0 for value in values):
        raise SystemExit(f'{name}: invalid performance measurements')
for key in ('rounds', 'requests', 'clients', 'idle', 'warmup_rounds'):
    if stock['config'][key] != filc['config'][key]:
        raise SystemExit(f'incomparable workload: {key}')
if stock['requests_checked'] != filc['requests_checked']:
    raise SystemExit('incomparable request counts')
for key in ('cpus', 'client_cpus', 'load_generator', 'driver_sha256', 'workload_sha256', 'limits', 'python', 'platform'):
    if stock['identity'][key] != filc['identity'][key]:
        raise SystemExit(f'incomparable measurement: {key}')
for key in ('ruby', 'puma', 'nio4r', 'threads', 'yjit', 'zjit'):
    if stock['identity']['server'][key] != filc['identity']['server'][key]:
        raise SystemExit(f'incomparable server: {key}')
failed = False
for key in ('median', 'peak'):
    baseline = stock['metrics']['rss_kb'][key]
    measured = filc['metrics']['rss_kb'][key]
    ratio = measured / baseline
    passed = ratio <= 1.05
    failed |= not passed
    print(f'RSS {key}: stock={baseline:.0f} KiB Fil-C={measured:.0f} KiB ratio={ratio:.3f}; '
          f'{"PASS" if passed else "FAIL"} (maximum 1.050)')
for name, result in (('stock', stock), ('Fil-C', filc)):
    rss = result['metrics']['rss_kb']
    growth = rss['late_growth'] / rss['median']
    passed = growth <= 0.05
    failed |= not passed
    print(f'{name} warmed RSS growth: {rss["late_growth"]:.0f} KiB ({growth:.1%}); '
          f'{"PASS" if passed else "FAIL"} (maximum 5%)')
    utilization = result['metrics']['performance']['max_round_client_cpu_utilization']
    passed = math.isfinite(utilization) and 0 <= utilization <= 0.8
    failed |= not passed
    print(f'{name} maximum round client CPU utilization: {utilization:.1%}; '
          f'{"PASS" if passed else "FAIL"} (maximum 80% of assigned client CPUs)')
baseline = stock['metrics']['performance']
measured = filc['metrics']['performance']
ratio = measured['requests_per_second'] / baseline['requests_per_second']
passed = ratio >= 0.95
failed |= not passed
print(f'Load throughput: stock={baseline["requests_per_second"]:.1f} req/s '
      f'Fil-C={measured["requests_per_second"]:.1f} req/s ratio={ratio:.3f}; '
      f'{"PASS" if passed else "FAIL"} (minimum 0.950)')
for percentile in ('p50', 'p95', 'p99'):
    reference = baseline['latency_ms'][percentile]
    observed = measured['latency_ms'][percentile]
    ratio = observed / reference
    passed = ratio <= 1.05
    failed |= not passed
    print(f'HTTP latency {percentile}: stock={reference:.3f} ms Fil-C={observed:.3f} ms ratio={ratio:.3f}; '
          f'{"PASS" if passed else "FAIL"} (maximum 1.050)')
print('Closed-loop checked load; warmup, idle and diagnostic GC are excluded from performance metrics.')
print('Finite workload stability does not prove absence of leaks in other workloads or longer runs.')
raise SystemExit(int(failed))
