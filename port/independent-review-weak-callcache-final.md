# Independent follow-up review: weak callcache class patch

**Baseline:** HEAD `74beca5480e31c26305e5ad7344fc428c553c8f2`  
**Reviewed artifact:** `/tmp/ruby-filc/port/weak-callcache-class-final.patch`

## Findings

No issues found.

## Verified evidence

### Patch scope and integrity

- The reviewed source diff contains the intended nine files:
  - `ext/objspace/objspace_dump.c`
  - `gc.c`
  - `gc/filc/filc.c`
  - `imemo.c`
  - `ractor_core.h`
  - `vm_callinfo.h`
  - `vm_core.h`
  - `vm_insnhelper.c`
  - `vm_method.c`
- The SHA-256 of the current nine-file source diff is identical to the supplied patch:
  `16aaf8701bf09dcb2e1146b3827db8b55f49f5cabdcacbbb26b1af2328cfe6e5`.
- There are no staged changes.
- The additional tracked modifications are generated files (`gc.rbinc`, `miniprelude.c`, `revision.h`, and `vm.inc`) and are not present in the authoritative patch.
- `git diff --check` reports no whitespace errors for the nine reviewed files.

### Prior P2 corrections

- `vm_insnhelper.c:5075-5079` now resolves the heap cache through `vm_cc_klass(cc)` and writes that direct class into `cc_on_stack.klass` before setting `VM_CALLCACHE_UNMARKABLE`. This preserves the invariant used by `vm_cc_klass()` that unmarkable caches contain a direct class rather than a `zweak *`.
- The supplied controlled red run records exit status 133 and the expected Fil-C failure on `special(weak)`, through `cc_check_class -> vm_cc_cme -> vm_call_method_each_type`.
- The restored implementation passes the protected getter/setter, forced-GC, and visibility probe with status 0.
- `ext/objspace/objspace_dump.c:454-466` binds the callcache once, reads `vm_cc_klass(cc)` once, and accesses the CME and emits `receiver_class` only when the resolved class is not `Qundef`.
- The dump probe fails before the correction with status 1 because `receiver_class` is not the class address, while the corrected and stock-Darwin logs report that all callcache receiver-class fields resolve to Ruby classes. The combined review-fix probe status is 0.

### Ractor metadata layout and initialization

- Under `RACTOR_CHECK_MODE`, `struct filc_object_fields` begins with `uint32_t ractor_id`, followed by compiler padding and the existing pointer-sized fields.
- On the reviewed 64-bit target, the Fil-C base slot is 40 bytes and the augmented tail structure is 24 bytes. For every size class, `slot_size + 24` remains below the next doubled size class. Therefore `rb_gc_impl_obj_slot_size()` continues returning only the Ruby object slot and excludes the tail metadata.
- `object_fields()` continues locating the tail relative to `zgetupper()`. Because allocation size is now `slot_size + sizeof(struct filc_object_fields)`, the first field is exactly at `obj + slot_size`, matching `RACTOR_BELONGING_ID`.
- The object address and every Fil-C slot size are pointer-aligned. Consequently the tail is suitably aligned for `uint32_t`, and the structure’s natural padding keeps `finalizer` and `gen_fields` pointer-aligned.
- `gc/filc/filc.c:474-478` zero-initializes the complete tail before calling `rb_ractor_setup_belonging()`. This matches the default collector’s new-object initialization ordering.
- `ractor_core.h:274` now uses capability-preserving `char *` arithmetic rather than converting the object pointer to an integer and back.
- Existing object-size consumers and Ractor copy paths use `rb_gc_obj_slot_size()`, so they continue excluding the ownership/finalizer/generic-field tail, consistent with the default collector’s treatment of Ractor overhead.
- Shareable objects still follow the existing `rb_ractor_belonging()` rule that returns zero without consulting stored ownership metadata.

### VM-check compile corrections

The added fixes preserve the checks instead of bypassing them:

- `vm_core.h:1743` uses the existing `VM_TAGGED_PTR_REF` helper for capability-preserving tagged block extraction.
- `vm_callinfo.h:635-672` represents the native debug signature as `uintptr_t`, including creation, reallocation, duplication, and validation.
- `vm_insnhelper.c:140-230` represents frame flag bits as `uintptr_t`; the call site explicitly converts the pointer-typed `VALUE`, while `FIXNUM_P` still receives a `VALUE`.
- `vm_insnhelper.c:7427` performs the stack-canary bit operation through `uintptr_t` and converts the tagged value back to `VALUE`.
- Supplied build logs show the corresponding compile failures before these fixes:
  - tagged-pointer integer operation in `vmcheck-build.log`;
  - debug-signature complement in `vmcheck-build-2.log`;
  - frame-flag and canary operations in `vmcheck-build-3.log`;
  - the missing frame call-site conversion in `vmcheck-build-4.log`.
- `vmcheck-build-5.status` and `vmcheck-build-6.status` are both 0 and their logs end by linking `miniruby`.
- The successful VM-check protected-call probe also demonstrates that the resulting checked runtime starts and executes the corrected callcache path.

## Limitations

- Per instruction, I did not run builds, tests, or containers during this review.
- The separate build path recorded in `ta/vmcheck-build-path.txt` was no longer present during inspection, so validation of that build was limited to the supplied logs and status files.
- The full debug bootstrap was still in progress and is not part of this verdict.
- The supplied runtime evidence does not separately isolate cross-Ractor ownership transfer behavior, although the tail layout and initialization match the existing default-GC contract.
- The full normal test and spec runs predate the final debug-only/review corrections and contain the documented pre-existing port failures. They are not treated as a clean final-suite result.
- This review makes no claim about overall port completeness or the out-of-scope normal-CME and refinement-table retention work.

Merge verdict: OK with notes