#include <assert.h>
#include <stdlib.h>
#include <stdfil.h>
#include <string.h>

static int
needs_argument(int argument)
{
    return argument + 1;
}

int
main(int argc, char **argv)
{
    assert(argc == 2);
    volatile char *bytes = malloc(32);
    assert(bytes);
    volatile size_t length = zlength((void *)bytes);
    bytes[0] = 17;
    bytes[length - 1] = 23;
    assert(bytes[0] == 17 && bytes[length - 1] == 23);

    if (!strcmp(argv[1], "valid")) {
        int (*volatile function)(int) = needs_argument;
        assert(function(41) == 42);
        free((void *)bytes);
        return 0;
    }
    if (!strcmp(argv[1], "bounds")) {
        bytes[length] = 42;
    }
    else if (!strcmp(argv[1], "freed")) {
        free((void *)bytes);
        return bytes[0];
    }
    else if (!strcmp(argv[1], "readonly")) {
        volatile char *literal = (volatile char *)"read only";
        literal[0] = 'X';
    }
    else if (!strcmp(argv[1], "call")) {
        int (*volatile function)(void) = (int (*)(void))needs_argument;
        return function();
    }
    else {
        return 2;
    }
    free((void *)bytes);
    return 0;
}
