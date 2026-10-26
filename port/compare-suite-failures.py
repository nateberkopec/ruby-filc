import re
import sys
from pathlib import Path

results = []
for argument in sys.argv[1:]:
    path = Path(argument)
    text = path.read_text(errors='replace')
    failures = {
        item.split(' [', 1)[0].rstrip(':')
        for item in re.findall(r'^\s*\d+\) (?:Failure|Error):\n([^\n]+)', text, re.M)
    }
    results.append((path.name, failures))
    print(f'{path.name}: {len(failures)} failures/errors; '
          f'{text.count("filc safety error")} safety errors; '
          f'{text.count("Leaked file descriptor:")} descriptor warnings')
if results:
    current, failures = results[0]
    for baseline, previous in results[1:]:
        print(f'\n{current} vs {baseline}')
        print('Added:', sorted(failures - previous))
        print('Removed:', sorted(previous - failures))
