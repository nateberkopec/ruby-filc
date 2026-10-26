# Independent review: weak callcache class reference

**Baseline:** source HEAD `74beca5480e31c26305e5ad7344fc428c553c8f2` with the uncommitted five-file source patch. Generated tracked diffs were excluded.

## Findings

### P2 — Heap-to-stack callcache copy leaves the weak-cell address in a direct-class cache

**Paths:** `vm_insnhelper.c:5075-5078`, `vm_callinfo.h:423-426`, `vm_callinfo.h:470-471`

The protected-method path copies a heap callcache wholesale:

```c
struct rb_callcache cc_on_stack = *cc;
FL_SET_RAW((VALUE)&cc_on_stack, VM_CALLCACHE_UNMARKABLE);
```

Under Fil-C, the copied `klass` is still the heap cache’s native `zweak *`. After `VM_CALLCACHE_UNMARKABLE` is set, however, `vm_cc_klass()` treats that field as a direct Ruby class and returns the weak-cell address unchanged.

The default build can appear to work because the relevant checks in `vm_cc_cme()` are `VM_ASSERT`-only. A `VM_CHECK_MODE` build reaches `cc_check_class(vm_cc_klass(cc))` while executing the copied cache and attempts to validate the native weak-cell address as a Ruby class. This also violates the stated invariant that stack/unmarkable caches store direct classes.

**Smallest fix:** Resolve the original cache’s class before or while making the stack copy, and replace `cc_on_stack.klass` with that resolved value before setting `VM_CALLCACHE_UNMARKABLE`. Add a focused protected-call regression under a VM-check configuration if available.

### P2 — ObjectSpace heap dumping still reads the encoded field directly

**Path:** `ext/objspace/objspace_dump.c:453-466`

`imemo_callcache` dumping still performs:

```c
VALUE klass = ((const struct rb_callcache *)obj)->klass;
```

For a live Fil-C heap cache, this emits the native weak-cell address as `"receiver_class"` rather than the Ruby class address. If the target has died, the weak-cell address still differs from `Qundef`, so the dump incorrectly treats the cache as valid and accesses `vm_cc_cme()`; in a VM-check build, that accessor rejects the dead cache.

This is the only remaining direct callcache-class reader found outside the Fil-C-excluded default-GC code in `imemo.c`.

**Smallest fix:** Bind the callcache once, obtain `klass` with `vm_cc_klass(cc)`, and gate the fields with `!UNDEF_P(klass)`. Add a dump-all check ensuring callcache `"receiver_class"` references the class object rather than a non-heap weak-cell address.

## Verified evidence

- The Fiber lifetime probe logs show exactly 10 survivors for patched Fil-C and stock Ruby in both baseline and dispatch modes.
- The old `74beca5` image reports 422 survivors for dispatch and exits with status 1, preserving the intended regression signal.
- The supplied patched build status is 0.
- The supplied btest run passes all 2,044 tests.
- The corrected focused suite reports 980 tests and 21,296 assertions with no failures or errors.
- `git diff --check` reports no whitespace errors in the five source files.
- The class input remains guarded through heap-cache construction, invalidation uses matching Fil-C atomic load/store operations, and the non-Fil-C `imemo.c` marking/update path remains conditionally unchanged.

## Limitations

- I could not execute the built ARM64 Linux binaries locally because their `/opt/fil/lib/ld-fil1-aarch64.so` interpreter is unavailable in this inspection environment.
- The two findings are established from the representation and control flow but were not dynamically reproduced.
- Full clean-image suites were still running separately and were not evaluated here.
- This review does not claim to diagnose the earlier residual one-object lifetime observations.
- The separately documented `cme_` and refinement-table lifetime issues were treated as out of scope.

Merge verdict: BLOCK