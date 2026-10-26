#include <pthread.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef __FILC__
#include <stdfil.h>
#endif
#ifndef ITERATIONS
#define ITERATIONS 200000
#endif

__attribute__((noinline)) static void invoke(void)
{
    jmp_buf env;
    if (_setjmp(env)) abort();
}

static void *worker(void *unused)
{
    for (int i = 0; i < ITERATIONS; i++) invoke();
    return NULL;
}

int main(void)
{
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
