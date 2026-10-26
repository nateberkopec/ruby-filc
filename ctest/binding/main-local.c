#include <dlfcn.h>

int main(void) {
    dlopen("./a.so", RTLD_LAZY | RTLD_GLOBAL);
    void *b = dlopen("./b.so", RTLD_LAZY | RTLD_LOCAL);
    void (*fn)(void) = dlsym(b, "Init_eval");
    fn();
}
