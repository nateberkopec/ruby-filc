Additional 0.686 reproduction that may be covered by this fix (I haven't tested the unreleased compiler). Found while porting Ruby 4, but this program has no Ruby dependency.

On optfil 0.686, Linux aarch64, Ubuntu 24.04, 40 threads repeatedly calling a function containing `_setjmp` exhaust an 8 GiB container. After round 1, five explicit collections leave FUGC reporting 29 KiB live while RSS is 7,364,180 KiB; round 2 is OOM-killed. GCC completes all four rounds at about 1.5 MiB RSS. I am not claiming this is a retained-object leak.

```c
#include <pthread.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef __FILC__
#include <stdfil.h>
#endif

__attribute__((noinline)) static void invoke(void) {
    jmp_buf env;
    if (_setjmp(env)) abort();
}
static void *worker(void *unused) {
    for (int i = 0; i < 200000; i++) invoke();
    return NULL;
}
int main(void) {
    for (int round = 0; round < 4; round++) {
        pthread_t threads[40];
        for (int i = 0; i < 40; i++)
            if (pthread_create(&threads[i], NULL, worker, NULL)) abort();
        for (int i = 0; i < 40; i++)
            if (pthread_join(threads[i], NULL)) abort();
#ifdef __FILC__
        for (int i = 0; i < 5; i++) zgc_request_and_wait();
#endif
        FILE *file = fopen("/proc/self/status", "r");
        char line[256];
        while (fgets(line, sizeof(line), file))
            if (!strncmp(line, "VmRSS:", 6)) printf("round=%d %s", round + 1, line);
        fclose(file);
        fflush(stdout);
    }
}
```

Compile with `/opt/fil/bin/filcc -O3 -pthread repro.c -o repro`, then run `env FUGC_VERBOSE=1 ./repro`.
