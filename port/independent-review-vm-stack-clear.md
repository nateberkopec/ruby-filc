# Independent review: Fil-C VM-stack retirement

## Finding

### P2 — Tailcall stack-overflow path retires the old frame without clearing it

**Files:** `vm_insnhelper.c:3587-3612`, `vm_insnhelper.c:389`, `vm_core.h:2025-2031`

The tailcall path intentionally postpones retirement clearing until the outgoing arguments have been copied and the replacement frame has been created:

```c
VALUE *end = vm_frame_stack_end(cfp);
vm_pop_frame_preserving_stack(ec, cfp, cfp->ep);
...
vm_push_frame(...);
...
if (end > ec->cfp->sp) memset(...);
```

However, `vm_push_frame()` performs `CHECK_VM_STACK_OVERFLOW0()` at `vm_insnhelper.c:389`. That macro calls the non-returning `vm_stackoverflow()` when the prospective callee's locals plus `stack_max` do not fit (`vm_core.h:2025-2031`).

At that point:

1. `vm_pop_frame_preserving_stack()` has already advanced `ec->cfp` to the caller.
2. The old tailcaller control frame and value-stack range have not been cleared.
3. The replacement frame has not been installed.
4. The `memset()` at `vm_insnhelper.c:3612` is unreachable.
5. Exception unwinding begins from the caller, so it never visits or clears the already-retired tailcaller.

On Fil-C, the stale capabilities in that retired range remain visible through the malloc-backed VM-stack allocation. A caller can rescue the `SystemStackError`, suspend the Fiber, and retain objects solely through those stale slots.

A precise reproduction shape is:

- Compile with `tailcall_optimization: true` and `trace_instruction: false`.
- Define a small tailcaller that records a string in a `WeakMap`, stores it in a high-index local, and tailcalls a no-argument method.
- Give the callee a body whose static evaluation `stack_max` exceeds the Fiber VM-stack capacity—for example, generate a method body containing a call with more than 16,384 literal arguments.
- Rescue `SystemStackError` in the tailcaller's caller, suspend the Fiber, run full/immediate GC, and enumerate the `WeakMap` keys.
- The retired tailcaller slot can retain the key because its clearing statement was bypassed. The successful-tailcall regression does not exercise this path.

**Smallest corrective change:** detect/preflight the prospective replacement frame's exact stack requirement while the outgoing frame is still available, or explicitly clear the outgoing frame before raising on that failure path. Preserve the successful path's current ordering so arguments and a current-frame block handler remain valid until copied. Add a regression covering a rescued tailcall frame-push `SystemStackError`.

## Verified review evidence

- Repository HEAD is `78e4bb76d8a940b37de2296f57c800a0caadd247`.
- The authoritative patch SHA256 is `38512a1fbdd51e378da9791f2e99ec1d922f7143e4b4ef54238027f8bd888c33`.
- The actual `vm_insnhelper.c` diff is byte-for-byte identical to that patch.
- `git diff --check -- vm_insnhelper.c` reports no errors.
- Existing evidence shows:
  - the exact Fiber/WeakMap probe passes with zero remaining keys;
  - focused normal, raise, throw, closure, C-frame, receiver, forwarding, successful-tailcall, and TracePoint cases have zero statuses;
  - closures preserve the expected ten live objects;
  - all 2,044 bootstrap tests pass.
- I did not run new tests or builds, per the read-only constraint.

## Scope notes

- Escaped environments are copied to heap storage before a `Proc`/binding can outlive its frame; clearing the retired stack copy is consistent with `vm_make_env_each()`.
- Native C-frame argument views remain valid while the C function is running: nested frames start at the C frame’s saved SP, and the C frame’s receiver/argv range is only cleared when that C function returns.
- Dummy ISeq frames are correctly excluded from the `stack_max` calculation because their real ISeq layout was not allocated as a normal Ruby frame.
- Non-Fil-C behavior remains effectively unchanged because clearing is guarded by `__FILC__`.
- This port is configured with YJIT and ZJIT disabled. If Fil-C JIT support is enabled later, direct JIT-generated frame pops and `rb_full_cfunc_return()` would require a separate retirement audit.
- Discarded operand slots inside a still-active frame are a broader conservative-tracing gap and are not treated as a defect in this bounded frame-pop patch.

Merge verdict: BLOCK