Each `zweak_map_set()` leaks about 400 bytes that are never reclaimed, even after the entry is removed. `zweak_map_size()` returns 0 and `FUGC_VERBOSE` shows a flat live heap, but RSS grows without bound. The same thing happens when keys just die instead of being removed. Churning `zweak_new()` or `zgc_finq_alloc()` the same way doesn't leak.

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdfil.h>

int main(void) {
    zweak_map *m = zweak_map_new();
    for (int round = 0; round < 8; round++) {
        for (int i = 0; i < 100000; i++) {
            void *key = malloc(64);
            zweak_map_set(m, key, key);
            zweak_map_set(m, key, NULL);
        }
        zgc_request_and_wait();
        char line[256];
        FILE *f = fopen("/proc/self/status", "r");
        while (fgets(line, sizeof line, f))
            if (!strncmp(line, "VmRSS:", 6)) printf("round %d: size=%zu %s", round, zweak_map_size(m), line);
        fclose(f);
    }
}
```

Output on Fil-C 0.686 (optfil, linux aarch64):

```
round 0: size=0 VmRSS: 63540 kB
round 7: size=0 VmRSS: 351456 kB
```

Found while porting Ruby 4.0 to Fil-C, which used a `zweak_map` per allocated object.
