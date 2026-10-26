# Independent follow-up review: revised Fil-C VM-stack retirement

## Findings

No issues found.

The original P2 tailcall-overflow cleanup bypass is resolved, and I found no new concrete defect caused or made reachable by the revised bounded patch.

## Patch identity

- Repository HEAD is `78e4bb76d8a940b37de2296f57c800a0caadd247`.
- The unstaged source diff is limited to:
  - `vm.c`: +14/-0
  - `vm_core.h`: +8/-2
  - `vm_insnhelper.c`: +61/-2
- The current source diff is byte-for-byte identical to `/tmp/ruby-filc/port/vm-stack-clear-revised.patch`.
- Both hashes are `9147af50928511bfe5b0e6b171228324c814b59ca33c6ad9bcaf18eec37023f6`.
- `git diff --check -- vm.c vm_core.h vm_insnhelper.c` reports no errors.
- Existing generated changes in `gc.rbinc`, `miniprelude.c`, `revision.h`, and `vm.inc` were excluded as instructed.

## Correctness audit

### Prior P2: tailcall replacement-frame overflow

**Files:** `vm_core.h:2025-2041`, `vm_insnhelper.c:3567-3623`

The new preflight at `vm_insnhelper.c:3605-3611` uses:

- the same prospective control frame, `RUBY_VM_NEXT_CONTROL_FRAME(cfp)`;
- the same post-copy `sp`; and
- the same local-plus-operand margin

that the subsequent `vm_push_frame()` passes to the ordinary stack-overflow check at `vm_insnhelper.c:3614-3618`.

On failure, it extends `end` through the copied receiver/arguments, clears the discarded outgoing control frame and value range, and only then calls the non-returning `vm_stackoverflow()`. Thus the cleanup no longer lies after the throwing operation.

The successful path remains ordered correctly:

1. The outgoing frame remains readable while its arguments are copied (`vm_insnhelper.c:3594-3603`).
2. A current-frame block handler is relocated before retirement (`vm_insnhelper.c:3576-3585`).
3. The replacement frame is fully installed before old surplus slots are cleared (`vm_insnhelper.c:3614-3623`).
4. Successful-call clearing starts at the replacement frame’s current SP, so copied parameters, initialized locals, and environment fields below that SP remain intact.

There is no intervening callback or allocation between the completed pop and the overflow preflight; only direct stack stores occur. The previous exception bypass is therefore closed.

### FrozenCore `REWIND_CFP`

**File:** `vm.c:3990-4011`

The Fil-C macro now saves the complete hidden `rb_control_frame_t` before advancing `ec->cfp`. This covers all frame state, including EP, self, ISeq, block code, JIT return state, and `bp_check` when enabled.

After the expression returns, it:

1. restores the hidden frame into `RUBY_VM_NEXT_CONTROL_FRAME(ec__->cfp)`;
2. executes a compiler fence; and
3. republishes the frame by decrementing `ec__->cfp`, while retaining the original caller-SP restoration.

This directly repairs the demonstrated failure mode in which nested alias/undef callbacks reused and cleared the temporarily hidden C-frame slot. A normal callback return can no longer reactivate a zeroed EP. On a nonlocal exception, control does not execute the restoration tail and therefore does not reactivate the hidden frame, preserving the original macro’s exception behavior.

The non-Fil-C macro is unchanged.

### Ordinary frame retirement and lifetimes

**Files:** `vm_insnhelper.c:437-505`, `vm_insnhelper.c:2717-2750`, `vm.c:1077-1155`

`vm_frame_stack_end()` covers the maximum of the live SP and the Ruby frame’s base plus `stack_max`. Forwardable local frames are handled through the existing `vm_base_ptr()` adjustment using the recorded call-info argument count. Dummy ISeq frames are excluded because their normal ISeq layout was not allocated.

`vm_clear_popped_frame()` starts at the now-active caller’s SP and clears through the computed outgoing end, followed by the retired control-frame header. The bounds assertions correspond to the VM’s value-stack/control-frame geometry.

The interrupt check remains before `ec->cfp` is advanced in `vm_pop_frame_preserving_stack()` (`vm_insnhelper.c:477-486`). If that check raises, the outgoing frame is still active and normal exception unwinding retires it; the helper does not prematurely clear a still-current frame.

Escaped closures and bindings remain valid because `vm_make_env_each()` copies the environment into heap storage before the stack frame can be retired. Tailcall block handlers that point into the outgoing CFP are moved before that CFP is cleared.

For C frames, clearing occurs only after the C invoker returns. The receiver, return value, and method entry needed by subsequent return hooks are already held in C locals (`vm_insnhelper.c:3951-3993`), while nested calls begin above the active C frame’s saved SP.

### Forwarding and tailcall geometry

**Files:** `vm_insnhelper.c:2717-2750`, `vm_insnhelper.c:3567-3623`

For an outgoing forwardable frame, `vm_base_ptr()` includes the dynamic forwarded argument count when determining the old reserved range. The successful tailcall cleanup starts at the replacement frame’s SP, rather than at the parent’s pre-call SP, so it cannot erase the replacement frame’s preserved argument/local area.

The overflow preflight exactly mirrors the subsequent `vm_push_frame()` geometry rather than introducing a second, differently calculated requirement. I found no introduced forwarding/tailcall overlap or off-by-one error.

The supplied runtime modes exercise forwarding and tailcalls separately; no explicit forwarding-plus-tailcall cross-product probe was present in the reviewed evidence. This is a validation limitation, not a source finding.

### Shared overflow predicate and non-Fil-C behavior

**File:** `vm_core.h:2025-2041`

The extracted `vm_stack_overflow_p()` preserves the original expression:

```c
const rb_control_frame_t *bound = (const void *)&sp[margin];
return cfp <= &bound[1];
```

The original compile-time size assertions remain in `CHECK_VM_STACK_OVERFLOW0`. Existing call sites still evaluate each argument once. All retirement clearing and the special `REWIND_CFP` behavior remain guarded by `__FILC__`; the original non-Fil-C rewind macro remains in the `#else` branch.

## Reviewed validation evidence

I did not build or run the Fil-C candidate; these results were verified from the supplied logs and status files.

- Normal and checked lifetime probes report `remaining=0`.
- Normal and checked rescued-tailcall-overflow probes report:
  - `remaining=0`
  - `alive=true`
  - `stack_max=20001`
- Normal and checked rewind probes report successful alias/undef callbacks.
- All nine retirement modes have zero statuses on both builds.
- Normal and checked bootstrap logs each report all 2,044 tests passing.
- Both regression aggregates have zero status.
- The full runtime/extensions build status is zero.

## Outstanding validation

Full `test-all`, spec, and C-API validation remains incomplete. The available test-all log is only a partial dispatch log, and no full-suite or aggregate success status exists. The focused evidence must not be treated as broad Ruby-suite acceptance.

The current configuration has YJIT disabled. Enabling a Fil-C JIT later would require a separate audit of JIT-specific frame-pop and lazy-frame paths; that is outside this bounded candidate.

Merge verdict: OK with notes