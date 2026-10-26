#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef __FILC__
#include <stdfil.h>
#endif

static jmp_buf *volatile current;

__attribute__((noinline)) static int run(void)
{
    jmp_buf buffer;
#ifdef ESCAPE
    current = &buffer;
#endif
    int result = setjmp(buffer);
#ifdef ESCAPE
    current = NULL;
#endif
    return result;
}

int main(void)
{
    for (int round = 0; round < 8; round++) {
        for (int i = 0; i < 100000; i++) {
            if (run()) abort();
        }
#ifdef __FILC__
        for (int i = 0; i < 5; i++) zgc_request_and_wait();
#endif
        FILE *file = fopen("/proc/self/status", "r");
        char line[256];
        while (fgets(line, sizeof(line), file)) {
            if (!strncmp(line, "VmRSS:", 6)) printf("round=%d %s", round + 1, line);
        }
        fclose(file);
        fflush(stdout);
    }
}
