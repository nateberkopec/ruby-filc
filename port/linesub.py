import re, sys

def hunks(patch):
    lines = open(patch).read().split('\n')
    i = 0
    while i < len(lines):
        if lines[i].startswith('@@'):
            i += 1
            block = []
            while i < len(lines) and not lines[i].startswith('@@') and not lines[i].startswith('diff '):
                block.append(lines[i])
                i += 1
            yield block
        else:
            i += 1

def pairs(block):
    i = 0
    while i < len(block):
        if block[i].startswith('-') or block[i].startswith('+'):
            rem, add = [], []
            while i < len(block) and block[i].startswith('-'):
                rem.append(block[i][1:]); i += 1
            while i < len(block) and block[i].startswith('+'):
                add.append(block[i][1:]); i += 1
            yield rem, add
        else:
            i += 1

patch, target = sys.argv[1], sys.argv[2]
apply = len(sys.argv) > 3 and sys.argv[3] == 'apply'
maxcount = 4
src = open(target).read().split('\n')
changed = 0
for block in hunks(patch):
    for rem, add in pairs(block):
        if len(rem) != len(add):
            if any(a not in src for a in add):
                print(f"SKIP-UNEVEN {len(rem)}->{len(add)}: {rem[:1]} => {add[:1]}")
            continue
        for r, a in zip(rem, add):
            if r == a:
                continue
            n = src.count(r)
            if n == 0:
                continue
            if n > maxcount:
                print(f"SKIP-FREQ x{n}: {r.strip()} => {a.strip()}")
                continue
            print(f"SUB x{n}: {r.strip()[:90]} => {a.strip()[:90]}")
            src = [a if l == r else l for l in src]
            changed += n
if apply:
    open(target, 'w').write('\n'.join(src))
print(f"{changed} lines", file=sys.stderr)
