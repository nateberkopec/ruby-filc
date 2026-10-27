# Draft: sparse mmap reservations inflate FUGC's allocation headroom

Status: local proposal, not submitted to upstream.

## Observation

With the Linux ARM64 optfil 0.687 release, keeping a 384 MiB anonymous mapping alive while touching only one byte substantially increases the RSS of an otherwise identical malloc/free workload. The workload allocates and immediately frees 200,000 1,024-byte objects, about 195.3 MiB in total. It does not retain those objects intentionally.

Three consecutive pairs, with the default concurrent collector:

| Reserved MiB | Automatic cycles during churn | Starting peak RSS, KiB | Final peak RSS, KiB |
|---:|---:|---:|---:|
| 0 | 180 | 13,896 | 16,240 |
| 384 | 0 | 16,880 | 217,648 |
| 0 | 8 | 13,904 | 84,760 |
| 384 | 1 | 17,016 | 218,368 |
| 0 | 180 | 13,908 | 16,236 |
| 384 | 0 | 17,124 | 223,124 |

The control has scheduling-dependent variation, but the reserved mapping consistently allows nearly the entire allocation stream to accumulate before collection. The large reservation itself does not initially consume hundreds of MiB of RSS. This is a collection-policy/retention observation, not evidence of a permanent leak.

## Reproduction

Save the following as `mmap-gc-pressure.c`. There are three explicit collections before the measured allocation loop, and none during that loop. Every temporary allocation is freed.

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

The upstream release archive SHA-256 is `375995867dcd3e91533efba6328a5057e51cf7db5a1ffa413ad391d0336ade6e`. This was run on Linux ARM64 through OrbStack, in an Ubuntu 24.04 container restricted to CPUs 0-3, 4 GiB RAM and no additional swap.

## Diagnosis and proposed direction

[`filc_native_zsys_mmap`](https://github.com/pizlonator/fil-c/blob/b8ffc50327d4fe8c4fe6e4fc2b9d823ed19966d8/libpas/src/libpas/filc_runtime.c) first allocates the full mapping length through `allocate_aligned_impl`, with `FILC_OBJECT_FLAG_MMAP`. In [`fugc.c`](https://github.com/pizlonator/fil-c/blob/b8ffc50327d4fe8c4fe6e4fc2b9d823ed19966d8/libpas/src/libpas/fugc.c#L1385-L1420), the next threshold is `surviving_bytes * fugc_threshold_multiplier`, whose default multiplier is 1.5. A surviving 384 MiB reservation therefore adds roughly 192 MiB of allocation headroom even when almost all of it is nonresident. The verbose run reports a threshold around 604 million bytes against roughly 403 million surviving bytes.

The `fugc.c` blob is identical in v0.687, my source-build checkout, and upstream commit `b8ffc50327d4fe8c4fe6e4fc2b9d823ed19966d8` (`f96818e4e0536ebb942139b8b7415610145a7df6`). The mmap allocation path is also still present at that upstream commit. I have not built or run that entire newer upstream revision.

Would separating the survivor footprint used to calculate **additional allocation headroom** from the full reserved allocation size fit FUGC's design? Large sparse mappings could remain fully tracked and new mappings could still contribute to allocation pressure, without an old reservation indefinitely granting proportional headroom to unrelated malloc/free churn. Any implementation also needs to handle sparse auxiliary pointer storage, mapping resize/unmap operations, concurrent accounting, and the CPU cost of more frequent collections. Simply excluding all mmap allocations from GC accounting would not be a sufficient fix.

The application motivation is Ruby's shape ancestor cache, which reserved 384 MiB up front. Replacing that cache with stable-address lazy chunks reduced our Puma application's measured median RSS by 59%, with no reduction in cache capacity. That application workaround does not solve the general reservation/accounting interaction.

Local source and receipts: `probes/c/mmap-gc-pressure.c`, `ta/mmap-gc-pressure-final.log`, and `ta/mmap-gc-pressure-free-verbose.log`.
