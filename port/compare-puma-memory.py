import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description='Require Puma RSS within 5% of stock and bounded warmed memory growth.')
parser.add_argument('stock', type=Path)
parser.add_argument('filc', type=Path)
args = parser.parse_args()
stock = json.loads(args.stock.read_text())
filc = json.loads(args.filc.read_text())
for key in ('rounds', 'requests', 'clients', 'idle'):
    if stock['config'][key] != filc['config'][key]:
        raise SystemExit(f'incomparable workload: {key}')
if stock['config'].get('warmup_rounds', 1) != filc['config'].get('warmup_rounds', 1):
    raise SystemExit('incomparable warmup')
if stock['requests_checked'] != filc['requests_checked']:
    raise SystemExit('incomparable request counts')
if 'identity' in stock and 'identity' in filc:
    if stock['identity']['cpus'] != filc['identity']['cpus']:
        raise SystemExit('incomparable CPU affinity')
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
print('Finite workload stability does not prove absence of leaks in other workloads or longer runs.')
raise SystemExit(int(failed))
