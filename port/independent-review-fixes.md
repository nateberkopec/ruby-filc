# Targeted follow-up review — GC/WeakMap fixes at `bc4a436`

## Review basis

- Repository: `/tmp/ruby-filc/ruby-4.0.7-glibc`
- HEAD: `bc4a436b267e80ab83c89e5ebfdce6df0496718e`
- Original report: `/tmp/ruby-filc/port/independent-review-bc4a436.md`
- Frozen incremental diff: `/tmp/ruby-filc/port/review-fixes.patch`
- The working-tree diff for `gc.c`, `gc/filc/filc.c`, and `weakmap.c` is byte-for-byte identical to the frozen patch.
- Generated files and build artifacts were excluded as requested.
- `git diff --check` found no whitespace errors in the targeted changes.

## Finding

### P2 — A concurrent `GC.disable` can restore retained roots before an already-requested explicit collection finishes

**Files:** `gc.c:4561-4564`, `gc/filc/filc.c:190-194`, `gc/filc/filc.c:340-370`

The new request list correctly delays the normal post-collection restoration at line 370 until the last explicit request finishes:

```c
if (registry->disabled && !registry->requests) {
    registry_set_retained(registry, true);
}
```

However, the public state-transition path bypasses that condition. When `GC.disable` changes the logical state from enabled to disabled, `registry_set_disabled` unconditionally restores all roots:

```c
if (registry->disabled != disabled) {
    registry->disabled = disabled;
    registry_set_retained(registry, disabled);
}
```

The following interleaving remains possible:

1. Ruby GC is enabled.
2. One Ractor enters `registry_collect`, obtains a fresh cycle, links its request into `registry->requests`, unlocks the registry, and waits in `zgc_wait`.
3. Another Ractor calls `GC.disable`.
4. The transition is atomic with respect to other public enable/disable calls because of the VM lock, but `GC.start` does not hold that lock while waiting.
5. `registry_set_disabled(..., true)` sees an actual false-to-true transition and strongly retains every currently live registered Ruby object even though the explicit request is still outstanding.
6. The pending native cycle consequently sees those objects as roots and can fail to reclaim objects that the explicit `GC.start` was intended to collect.

This also conflicts with the `finish_current_gc=true` argument passed by `rb_objspace_gc_disable` at `gc.c:4564`. The default collector honors that argument by finishing the active collection before disabling; the Fil-C implementation ignores it at `gc/filc/filc.c:190-194`.

The VM lock does not prevent this sequence: it serializes previous-state observation and public transitions, but `registry_collect` releases the registry mutex around `zgc_wait` and does not participate in the transition VM lock.

**Impact:** An explicit collection already in progress can be made ineffective by concurrent `GC.disable`, delaying weak-reference clearing, finalizers, and reclamation until a later explicit collection or re-enable. This is a remaining defect in the new request/retention state machine; the supplied overlap probes cover `GC.enable` during overlap, but not an enabled-to-disabled transition during overlap.

**Smallest correction:** When transitioning to disabled, bulk-retain existing objects only if there is no outstanding explicit request:

```c
registry_set_retained(registry, disabled && !registry->requests);
```

The existing last-request path at line 370 will then establish retention after all requested cycles finish. `registry_add` can continue retaining objects allocated after the disable transition; such objects were allocated after the pending cycle was requested and ordinarily float through that cycle.

No new P1 issue was found.

## Original-finding dispositions

### 1. Concurrent `GC.enable` overwrite — resolved

The exact original P1 is fixed:

- `registry.disabled` remains the logical user-visible state throughout explicit collection.
- `registry_collect` releases retained roots without temporarily changing that logical state.
- Concurrent explicit requests are linked and retention is restored only after the last request finishes.
- Public enable/disable previous-state observation and mutation are serialized with `RB_GC_VM_LOCK_NO_BARRIER`.
- Lock ordering in the changed paths is consistent: transitions use VM lock then registry mutex; collection/count paths do not acquire the VM lock while holding the registry mutex.
- The transition path performs no Ruby allocation or callback while holding these locks, so no new reentrancy/unwind hazard was identified.

Supplied evidence:

- `review-enable_race-after.log`: `[true, false]`
- `review-enable-race-repeat.log`: five additional fresh-process `[true, false]` results
- `review-atomic_transitions-after.log`: all 160 Ractor transitions passed
- `review-enable_during_overlap-after.log`: `[true, false]`
- `review-overlap-after.log`: four overlapping requests completed and disabled state remained in force

Thus the temporary-state exposure and lost concurrent enable from the original report are no longer present.

### 2. Automatic cycles incrementing `GC.count` while disabled — resolved

The new counter correctly separates native cycle progress from Ruby-visible collection count:

- While enabled, newly completed native cycles are accumulated from `completed - counted_cycle`.
- While disabled, only completed cycle numbers represented by active explicit requests are counted.
- `registry_update_gc_count` runs under the registry mutex before logical state transitions, at request registration/completion, and on count reads.
- Each disabled explicit request is updated before its request node is removed, preventing a completed request from being missed.
- `zgc_request_fresh` is documented to request a later fresh cycle, and the runtime implementation uses `request_impl(1)`, which assigns monotonically increasing request numbers. Overlapping explicit requests therefore correspond to distinct native cycles.
- If another waiter accounts for multiple completed requests first, advancing `counted_cycle` prevents later waiters from double-counting them.
- `GC.stat` now captures the count once and uses that same value for `:count` and `:major_gc_count`.

Supplied evidence:

- Before: `disabled_count=[5, 6]`
- After: `disabled_count=[4, 4]`
- Explicit collection while disabled then produced `explicit_count=5`
- Four overlapping explicit requests changed the visible count from 5 to 9
- `review-fork_count-after.log`: inherited count and explicit collection in the child passed

No count duplication or loss was found in the inspected enable/disable and overlapping-request interleavings.

### 3. WeakMap per-entry memory accounting — resolved

`weakmap.c:195` now uses:

```c
st_table_size(w->table) * sizeof(struct weakmap_entry)
```

This accounts for all four Fil-C entry fields rather than only the two `VALUE` fields. It also matches the allocation/free size used throughout the implementation.

Supplied evidence for 100 entries:

- Before: `[5064, 5064]`
- After: `[6664, 5064]`

The 1,600-byte increase is exactly 100 entries × two additional 8-byte weak-handle pointers. The original minimum accounting defect is resolved.

## Coverage and gaps

Performed:

- Established HEAD and targeted working-tree state.
- Confirmed the inspected source diff exactly matches the frozen patch.
- Inspected the logical-state, request-list, retained-root, counter, VM-lock, registry-lock, `GC.stat`, fork-hook, and WeakMap allocation/accounting paths.
- Checked the documented `zgc_request_fresh`, `zgc_wait`, and completed-cycle APIs and their runtime implementations.
- Reviewed all supplied before/after targeted logs, including the six fresh-process race results, 160-Ractor transitions, overlap, enable-during-overlap, fork, disabled-count, and WeakMap probes.

Not performed:

- No compilation, source modification, container interference, or heavy suite execution.
- The local binary is architecture-incompatible with the review host, so supplied runtime logs were used rather than independently rerunning them.
- The reported concurrent-disable defect is source-proven but lacks a supplied runtime reproduction; the supplied overlap probe exercises concurrent enable, not disable.
- The supplied fork probe does not combine fork with an outstanding explicit request. Source inspection found the existing VM barrier and registry lock ordering consistent, but that precise stress case was not independently executed.
- Actual retained-root clearing/restoration was inspected directly in source; there was no dedicated weak-reference/finalizer retention probe covering every transition interleaving.

**Merge verdict: BLOCK**