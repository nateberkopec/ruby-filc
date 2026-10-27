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
