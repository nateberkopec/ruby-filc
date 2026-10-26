# Focused review — commit `74beca5`

## Findings

**No issues found.**

The Fil-C path is genuinely GC-safe rather than merely suppressing the former assertion:

- `class_descendants` now builds the result in one traversal, immediately placing each live non-singleton class into the Ruby array (`class.c:2167-2169`, `class.c:2185-2189`). This removes the unsafe count/allocate/enumerate interval while retaining the original two-pass implementation unchanged for non-Fil-C builds (`class.c:2190-2209`).
- Subclass-list mutation is serialized with the same VM lock used by the new traversal. Insertion and dead-entry pruning occur inside `RB_VM_LOCKING` (`class.c:526-545`), while traversal holds that lock across all array growth (`class.c:2187-2189`). Consequently, concurrent Ractors cannot splice or prune list nodes during enumeration.
- Concurrent Fil-C collection can clear weak class references, but dead references are skipped by `rb_class_foreach_subclass` (`internal/class.h:46-53`, `class.c:643-660`). Existing Fil-C pruning only unlinks dead nodes and does not immediately free them (`class.c:487-505`), so the saved `cur`/`tmp` node capabilities remain valid if GC completes during `rb_ary_push`.
- A live class obtained from a weak entry is held in the callback’s local `klass` and then strongly retained by the result array before recursive descent. Array growth retains no raw array-storage pointer across allocation.
- `rb_ary_push` failure does not permanently leak the VM lock: Ruby exception tags record lock depth and release excess recursive lock levels during unwind (`eval_intern.h:98-105`, `eval_intern.h:131-137`; `vm_sync.c:282-298`).
- No new lock-order inversion was identified. Array allocation under the VM lock may enter Fil-C collection and its registry mutex, matching existing VM-lock-before-registry paths.
- The exact parent-to-commit diff is limited to the intended 13 additions in `class.c`; `git diff --check` reported no errors.

## Runtime evidence inspected

- Before the fix, the standalone concurrent-GC probe exited `133` and reached the exact `rb_bug` assertion.
- After the fix, its recorded status is `0`; it preserved all 10,000 held subclasses over 100 concurrent-GC enumerations and all 18,000 subclasses after concurrent Ractor insertion and forced-GC traversal.
- The supplied focused regression run reports 375 tests and 14,036 assertions with no failures or errors.
- The parent clean-suite log confirms the original failure occurred in `TestClass#test_subclass_gc_stress`.

## Coverage limitations

- Per instruction, no compilation, container execution, or additional runtime tests were performed during this review.
- A complete post-fix clean full-suite result was not available; validation was limited to the supplied focused suite and concurrency probe logs.
- The supplied stress probes exercise array growth, concurrent collection, and concurrent insertion, but cannot exhaust every scheduler interleaving or inject allocation failure at each individual `rb_ary_push`.

**Merge verdict: OK**