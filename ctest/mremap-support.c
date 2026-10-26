#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void)
{
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    int modes[] = { MAP_PRIVATE, MAP_SHARED };
    for (int i = 0; i < 2; i++) {
        void *base = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | modes[i], -1, 0);
        if (base == MAP_FAILED) return 1;
        memcpy(base, "test", 4);
        errno = 0;
        void *resized = mremap(base, page, page * 2, MREMAP_MAYMOVE);
        if (resized == MAP_FAILED) {
            printf("%s: errno=%d (%s)\n", i ? "shared" : "private", errno, strerror(errno));
            if (munmap(base, page)) return 2;
        }
        else {
            printf("%s: resized, preserved=%d\n", i ? "shared" : "private", !memcmp(resized, "test", 4));
            if (memcmp(resized, "test", 4)) return 3;
            if (munmap(resized, page * 2)) return 4;
        }
    }
    return 0;
}
