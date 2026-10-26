Correction: identical file names aren't necessary. `RTLD_LOCAL` on the second library also reproduces it if the first is global.

`a.c`:
```c
#include <stdio.h>
void Init_eval(void) { puts("a"); }
```

`b.c` is the same but prints `b`. `main.c`:
```c
#include <dlfcn.h>
int main(void) {
    dlopen("./a.so", RTLD_LAZY | RTLD_GLOBAL);
    void *b = dlopen("./b.so", RTLD_LAZY | RTLD_LOCAL);
    void (*fn)(void) = dlsym(b, "Init_eval");
    fn();
}
```

```
filcc -shared -fPIC -o a.so a.c
filcc -shared -fPIC -o b.so b.c
filcc -o main main.c
./main
```

Prints `a` on optfil 0.686, Linux aarch64. Rebuilding all three with GCC prints `b`. Adding `RTLD_DEEPBIND` to the second dlopen also gives `b` with Fil-C.
