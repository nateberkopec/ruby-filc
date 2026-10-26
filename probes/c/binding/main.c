#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (!dlopen("./a.so", RTLD_LAZY | RTLD_GLOBAL)) return 1;
    void *b = dlopen("./b.so", RTLD_LAZY | atoi(argv[1]));
    if (!b) { puts(dlerror()); return 1; }
    void (*fn)(void) = dlsym(b, "Init_eval");
    if (!fn) { puts(dlerror()); return 1; }
    fn();
}
