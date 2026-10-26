When two libraries share a file name (here `a/lib.so` and `b/lib.so`) and are both opened with `RTLD_GLOBAL`, `dlsym()` on the second handle returns the first library's symbol. glibc built with gcc returns the second library's symbol. Fil-C also does with `RTLD_LOCAL`.

```c
// a/lib.c (b/lib.c is the same but prints "b/lib.so")
#include <stdio.h>
void init(void) { puts("a/lib.so"); }

// main.c
#include <dlfcn.h>

int main(void) {
    void *a = dlopen("./a/lib.so", RTLD_LAZY | RTLD_GLOBAL);
    void *b = dlopen("./b/lib.so", RTLD_LAZY | RTLD_GLOBAL);
    void (*init_b)(void) = dlsym(b, "init");
    init_b();
}
```

```
$ filcc -shared -fPIC -o a/lib.so a/lib.c && filcc -shared -fPIC -o b/lib.so b/lib.c && filcc -o main main.c && ./main
a/lib.so
```

Expected `b/lib.so`. Fil-C 0.686 (optfil, linux aarch64).

Found while porting Ruby to Fil-C: Ruby's `cgi/escape.so` and `erb/escape.so` both export `Init_escape`, so `require "erb"` ran the wrong init function.
