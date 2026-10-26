import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
names = {}
peaks = {}
samples = []
for line in path.open():
    row = json.loads(line)
    if row['type'] == 'process':
        names[row['id']] = row['args']
        continue
    for process in row['processes']:
        process['args'] = names.get(process['id'], [])
        if process['rss_kb'] > peaks.get(process['id'], {}).get('rss_kb', 0):
            peaks[process['id']] = dict(process, t=row['t'])
    samples.append(row)
first = samples[0]
last = samples[-1]
print('Event deltas:', {key: value - first['events'][key] for key, value in last['events'].items()})
print('Highest per-process RSS:')
for peak in sorted(peaks.values(), key=lambda p: p['rss_kb'], reverse=True)[:12]:
    print(json.dumps(peak))
indices = {max(range(len(samples)), key=lambda i: samples[i]['current'])}
for i in range(1, len(samples)):
    if samples[i]['events']['oom_kill'] != samples[i - 1]['events']['oom_kill']:
        indices.update(range(max(0, i - 3), min(len(samples), i + 3)))
for i in sorted(indices):
    row = samples[i]
    print(json.dumps({key: row[key] for key in ['t', 'current', 'events', 'stat']}))
    for process in row['processes'][:6]:
        print(json.dumps(process))
