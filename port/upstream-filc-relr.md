# Draft: packed relative relocations can produce unloadable Fil-C shared libraries

Status: local bug report/proposal, not submitted to upstream.

## Observation

With Linux ARM64 optfil 0.687, a small shared library works normally but fails `dlopen` when linked with `-Wl,-z,pack-relative-relocs`:

```text
./relr-packed.so: DT_RELR without GLIBC_ABI_DT_RELR dependency
```

The packed library has `DT_RELR`, includes `libc.so.6666` in `DT_NEEDED`, and has a `GLIBC_2.17` version requirement on `libyolocimpl.so`. It has no `GLIBC_ABI_DT_RELR` version requirement. Both the Fil-C libc and `libyolocimpl.so` provide that ABI version, but the link did not record the dependency.

This prevents enabling relocation packing generally for Ruby's native extensions. Ruby's `monitor.so` is one real example. Packing the much larger `libruby` itself works: that library already has ordinary version requirements on `libc.so.6666`, and its packed link gains the required ABI version.

## Reproduction

Save as `relr-dlopen.c`:

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

The first invocation prints `loaded and called answer()` and exits zero. The second prints the loader error above and exits one. The bundled linker reports `GNU ld (GNU Binutils) 2.47.20260726`. The release archive SHA-256 is `375995867dcd3e91533efba6328a5057e51cf7db5a1ffa413ad391d0336ade6e`.

## Diagnosis and proposed fix

The glibc loader's `elf/dl-version.c` rejects an object when it has version requirements, a `libc.so.*` dependency and `DT_RELR`, but no recorded `GLIBC_ABI_DT_RELR` requirement. The failing Fil-C output satisfies that rejection condition. This is not a loader lacking RELR support: the same loader runs packed `libruby` successfully.

The proposed fix is to make the link emit the required ABI dependency for this dependency arrangement, rather than disabling the loader's compatibility check. In particular, a libc that provides `GLIBC_ABI_DT_RELR` may need a version-need entry even when the other versioned references all resolve to `libyolocimpl.so`. The precise linker/driver change still needs investigation. Adding `-Wl,-u,GLIBC_ABI_DT_RELR` alone does not fix it; it still emits no required ABI version.

As a control, GCC-produced objects linked against the system libc with the same bundled GNU ld load successfully with `DT_RELR`. Their version requirements include both `GLIBC_2.17` and `GLIBC_ABI_DT_RELR` on `libc.so.6`. This control uses a temporary `-B` linker directory and `-fno-use-linker-plugin` to avoid trying to load GCC's native LTO plugin into the Fil-C linker. The Ubuntu system linker by itself warns that packing is unsupported on this target; that ignored-option attempt is not the packed control.

Once this is fixed, would enabling packing by default for the matched Linux/glibc toolchain be appropriate? On our Ruby 4.0.9 library, 843,010 relative relocations dominate the original relocation section. Relinking the same objects with packing reduces `.rela.dyn` from 20,458,992 to 226,752 bytes and adds a 228,072-byte `.relr.dyn`; `.rela.plt` is unchanged. This is about 19 MiB less relocation metadata, without removing safety checks, stack-trace metadata or generated machine code.

For now our Ruby build limits packing to the interpreter and `libruby`, leaving native-extension flags unchanged. This is a bounded application-side workaround, not a general toolchain fix. The observation is from the released toolchain; I have not verified the complete newer upstream toolchain.

Local source and receipts: `probes/c/relr-dlopen.c`, `ta/relr-dlopen-release.log`, `ta/relr-monitor-link.log`, `ta/relr-dlopen-gcc-matched-linker.log`, and `ta/relr-build.log` (the failed global-flag build).
