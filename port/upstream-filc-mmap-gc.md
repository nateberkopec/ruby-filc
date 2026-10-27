# Sparse mmap reservations inflate FUGC's allocation headroom

I'm porting Ruby 4.0.9 to Fil-C and measuring a Puma app's memory. Ruby's shape ancestor cache reserves 384 MiB; replacing it with lazy chunks cut median RSS by 59%. A FUGC-level fix would help avoid Ruby-specific allocation workarounds for sparse reservations.

The [1.5x survivor threshold](https://github.com/pizlonator/fil-c/blob/b8ffc50327d4fe8c4fe6e4fc2b9d823ed19966d8/libpas/src/libpas/fugc.c#L1385-L1420) gives that reservation roughly 192 MiB of extra allocation headroom, despite almost all of it being nonresident. Could reserved size be separated from the footprint used to calculate **additional headroom**, while preserving mapping tracking and pressure from new allocations?

On optfil 0.687 / Linux ARM64, touching one byte in a 384 MiB mapping changes an otherwise identical malloc/free workload:

| Three runs | Automatic GC cycles | Peak RSS, KiB |
|---|---:|---:|
| No mapping | 8-180 | 16,236-84,760 |
| Sparse mapping | 0-1 | 217,648-223,124 |

Starting peaks were below 18 MiB. The control varies with scheduling; this is retention behavior, not proof of a permanent leak.

<details>
<summary>Standalone reproducer: mmap-gc-pressure.c</summary>

Every temporary allocation is freed. Explicit collections occur only before the allocation loop.

```c
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdfil.h>
#include <sys/mman.h>
#include <sys/resource.h>

static void *mapping;
static unsigned char *volatile allocation;

__attribute__((noinline)) static void
allocate_garbage(unsigned value)
{
    unsigned char *object = malloc(1024);
    assert(object);
    object[0] = (unsigned char)value;
    allocation = object;
    free(object);
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    char *end;
    unsigned long mib = strtoul(argv[1], &end, 10);
    assert(*argv[1] && !*end && mib <= 1024);
    size_t size = mib * 1024 * 1024;
    if (size) {
        mapping = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        assert(mapping != MAP_FAILED);
        *(unsigned char *)mapping = 42;
    }
    for (unsigned i = 0; i < 3; i++) zgc_request_and_wait();
    zscavenge_synchronously();
    struct rusage start;
    assert(!getrusage(RUSAGE_SELF, &start));
    zgc_cycle_number before = zgc_completed_cycle();
    for (unsigned i = 0; i < 200000; i++) allocate_garbage(i);
    allocation = NULL;
    struct rusage usage;
    assert(!getrusage(RUSAGE_SELF, &usage));
    printf("mapping_mib=%lu allocated_mib=195 cycles=%llu starting_peak_rss_kib=%ld peak_rss_kib=%ld\n",
           mib, (unsigned long long)(zgc_completed_cycle() - before), start.ru_maxrss, usage.ru_maxrss);
    if (size) {
        assert(*(unsigned char *)mapping == 42);
        assert(!munmap(mapping, size));
    }
    return 0;
}
```

```sh
/opt/fil/bin/filcc -O2 -g -Wall -Wextra -Werror mmap-gc-pressure.c -o mmap-gc-pressure
./mmap-gc-pressure 0
./mmap-gc-pressure 384
FUGC_VERBOSE=4 ./mmap-gc-pressure 384
```

</details>

Upstream issue: [#351](https://github.com/pizlonator/fil-c/issues/351).
