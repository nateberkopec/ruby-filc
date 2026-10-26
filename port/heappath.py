import re, sys
from collections import defaultdict, deque

heap, targets_file = sys.argv[1], sys.argv[2]
edge = re.compile(r'^(global|thread\((0x[0-9a-f]+)\)|object\((0x[0-9a-f]+)\))->(0x[0-9a-f]+)(?:\((0x[0-9a-f]+)\))?$')
fwd = defaultdict(list)
roots = []
for line in open(heap):
    m = edge.match(line.strip())
    if not m:
        continue
    dst = int(m.group(5) or m.group(4), 16)
    ptr = int(m.group(4), 16)
    if m.group(1) == 'global':
        src = ('global', 0)
    elif m.group(2):
        src = ('thread', int(m.group(2), 16))
    else:
        src = ('object', int(m.group(3), 16))
    if src[0] != 'object':
        roots.append((src, ptr, dst))
    else:
        fwd[src[1]].append((ptr, dst))

raw = [int(t, 16) for t in open(targets_file).read().split()]
nodes = set(fwd) | {d for es in fwd.values() for _, d in es} | {d for _, _, d in roots}
targets = set()
for v in raw:
    hit = [b for b in range(v - 64, v + 1) if b in nodes]
    targets.add(max(hit) if hit else v)
prev = {}
q = deque()
for src, ptr, dst in roots:
    if dst not in prev:
        prev[dst] = (src, ptr)
        q.append(dst)
while q:
    n = q.popleft()
    for ptr, d in fwd.get(n, ()):
        if d not in prev:
            prev[d] = (('object', n), ptr)
            q.append(d)

found = 0
for t in sorted(targets):
    if t not in prev:
        print(f"{t:#x}: unreachable")
        continue
    found += 1
    if found > 3:
        continue
    path, n = [], t
    while True:
        src, ptr = prev[n]
        path.append(f"{n:#x} (via ptr {ptr:#x})")
        if src[0] != 'object':
            path.append(f"ROOT {src[0]} {src[1]:#x}")
            break
        n = src[1]
    print(f"== {t:#x}")
    for p in reversed(path):
        print("   ", p)
print(f"{found}/{len(targets)} reachable")
