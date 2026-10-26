#include <pthread.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#ifdef __FILC__
#include <stdfil.h>
#endif

static __thread jmp_buf *volatile current;
static int iterations;

__attribute__((noinline)) static int run(void)
{
    jmp_buf buffer;
    current = &buffer;
    int result = _setjmp(buffer);
    current = NULL;
    return result;
}

static void *worker(void *unused)
{
    for (int i = 0; i < iterations; i++) {
        if (run()) abort();
    }
    return NULL;
}

int main(int argc, char **argv)
{
    int count = argc > 1 ? atoi(argv[1]) : 40;
    iterations = argc > 2 ? atoi(argv[2]) : 200000;
    pthread_t *threads = calloc(count, sizeof(*threads));
    for (int round = 0; round < 4; round++) {
        for (int i = 0; i < count; i++) {
            if (pthread_create(&threads[i], NULL, worker, NULL)) abort();
        }
        for (int i = 0; i < count; i++) {
            if (pthread_join(threads[i], NULL)) abort();
        }
#ifdef __FILC__
        for (int i = 0; i < 5; i++) zgc_request_and_wait();
#endif
        FILE *file = fopen("/proc/self/status", "r");
        char line[256];
        struct rusage usage;
        if (getrusage(RUSAGE_SELF, &usage)) abort();
        while (fgets(line, sizeof(line), file)) {
            if (!strncmp(line, "VmRSS:", 6)) printf("round=%d peak=%ldKB %s", round + 1, usage.ru_maxrss, line);
        }
        fclose(file);
        fflush(stdout);
    }
    free(threads);
}
