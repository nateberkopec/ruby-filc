# Packed relative relocations can produce unloadable Fil-C shared libraries

While porting Ruby 4.0.9 to Fil-C, I found that packing `libruby`'s relative relocations saves about 19 MiB of mapped metadata without removing safety checks. But enabling packing globally breaks loading of Ruby's `monitor.so`, so our build currently limits it to the interpreter and `libruby`.

Fixing this would let us extend packing to native extensions. Would making packing the default for the matched Linux/glibc toolchain also be worth considering?

With optfil 0.687 on Linux ARM64, a tiny shared library linked with `-Wl,-z,pack-relative-relocs` fails `dlopen`:

```text
./relr-packed.so: DT_RELR without GLIBC_ABI_DT_RELR dependency
```

It has `DT_RELR` and a `libc.so.6666` dependency, but its only version requirement is `GLIBC_2.17` on `libyolocimpl.so`. The missing ABI requirement triggers glibc's loader check. Packed `libruby` records that requirement and loads successfully.

Could the linker emit the required ABI dependency for this arrangement, rather than disabling the loader check? The precise fix still needs investigation.

<details>
<summary>Standalone reproducer: relr-dlopen.c</summary>

```c
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
```

```sh
/opt/fil/bin/filcc -O2 -Wall -Wextra -Werror relr-dlopen.c -ldl -o relr-dlopen
/opt/fil/bin/filcc -O2 -fPIC -shared -DLIBRARY relr-dlopen.c -o relr-plain.so
/opt/fil/bin/filcc -O2 -fPIC -shared -DLIBRARY relr-dlopen.c \
  -Wl,-z,pack-relative-relocs -o relr-packed.so
./relr-dlopen ./relr-plain.so
./relr-dlopen ./relr-packed.so
readelf -d relr-packed.so
readelf -V relr-packed.so
```

The plain library prints `loaded and called answer()` and exits zero; the packed library prints the loader error and exits one. Bundled linker: GNU ld 2.47.20260726.

</details>

Upstream issue: [#352](https://github.com/pizlonator/fil-c/issues/352).
