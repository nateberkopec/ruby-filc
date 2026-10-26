#include <pthread.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdfil.h>

__attribute__((noinline)) static void invoke(void)
{
    jmp_buf env;
    if (_setjmp(env)) abort();
}

static void *worker(void *unused)
{
    for (int i = 0; i < 200000; i++) invoke();
    return NULL;
}

static void report(int round, const char *phase)
{
    FILE *file = fopen("/proc/self/status", "r");
    if (!file) abort();
    char line[256];
    while (fgets(line, sizeof(line), file))
        if (!strncmp(line, "VmRSS:", 6)) printf("round=%d phase=%s %s", round, phase, line);
    fclose(file);
    fflush(stdout);
}

int main(void)
{
    for (int round = 1; round <= 4; round++) {
        pthread_t threads[40];
        for (int i = 0; i < 40; i++)
            if (pthread_create(&threads[i], NULL, worker, NULL)) abort();
        for (int i = 0; i < 40; i++)
            if (pthread_join(threads[i], NULL)) abort();
        for (int i = 0; i < 5; i++) zgc_request_and_wait();
        report(round, "collected");
        zscavenge_synchronously();
        report(round, "scavenged");
    }
}
