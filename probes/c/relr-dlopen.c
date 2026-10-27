#ifdef LIBRARY

int answer(void)
{
    return 42;
}

#else

#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    assert(argc == 2);
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        fprintf(stderr, "%s\n", dlerror());
        return 1;
    }
    int (*function)(void) = dlsym(library, "answer");
    const char *error = dlerror();
    if (error) {
        fprintf(stderr, "%s\n", error);
        return 1;
    }
    assert(function() == 42);
    assert(!dlclose(library));
    puts("loaded and called answer()");
    return 0;
}

#endif
