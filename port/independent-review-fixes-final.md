# Final narrow follow-up — concurrent `GC.disable` correction

## Review basis

- Repository HEAD: `bc4a436b267e80ab83c89e5ebfdce6df0496718e`
- Targeted files: `gc.c`, `gc/filc/filc.c`, and `weakmap.c`
- The targeted working-tree diff matches `/tmp/ruby-filc/port/review-fixes-final.patch`.
- Comparing the previous and final frozen patches shows one substantive change:

```c
registry_set_retained(registry, disabled && !registry->requests);
```

- `git diff --check` reported no whitespace errors.
- This was a narrow follow-up; the prior 141-file audit was not repeated.

## Disposition

**No issues found.**

The one-line guard resolves the remaining P2 concurrent-disable finding without an evidence-backed regression in the reviewed path.

### Why the correction is sufficient

All relevant access to `registry->disabled`, `registry->requests`, and retained-root updates is serialized by `registry->lock`:

1. `registry_collect` registers its request before releasing the mutex (`gc/filc/filc.c:354-361`).
2. If `GC.disable` then changes the logical state, `registry_set_disabled` observes the outstanding request and does not restore existing retained roots (`gc/filc/filc.c:340-348`).
3. The pending collection can therefore reclaim objects that were unreachable when it was requested.
4. After completion, the request is removed under the same mutex, and retained roots are restored only when the logical state is still disabled and the request list is empty (`gc/filc/filc.c:365-371`).

The opposite ordering also remains correct: if disable happens before request registration, existing objects are initially retained, but `registry_collect` observes the disabled state and clears those roots before requesting its cycle. Concurrent enable and overlapping-request behavior are unchanged: enable leaves roots released, and only the last outstanding request can restore them.

Objects registered after disable remain individually retained through `registry_add` (`gc/filc/filc.c:276-295`). Thus the correction permits the already-requested collection to finish without exposing post-disable allocations to unintended reclamation.

The guard adds no lock acquisition, callback, allocation, or change in lock ordering.

## Runtime evidence inspected

The supplied reproduction logs confirm the exact failure and correction:

- Previous candidate:
  - Delays `0.001`, `0.005`, and `0.01` each reported `remaining=1000` and raised `concurrent disable prevented explicit collection`.
  - Delays `0.02` and `0.04` reported `remaining=0`, consistent with missing the race.
- Corrected candidate:
  - All five delays (`0.001`, `0.005`, `0.01`, `0.02`, and `0.04`) reported `remaining=0 previous=false` without an exception.
  - Successful script completion also means its final assertion verified that the logical disabled state was preserved until `GC.enable`.

The targeted bootstrap fork log reports all five `test_fork.rb` tests passing. The five exact fresh-process fork logs are empty, consistent with silent successful probes as described by the task, though their commands and exit statuses are not encoded in those files.

## Limitations and notes

- Per instruction, I did not compile, run container workloads, or execute additional tests.
- The timing reproduction is scheduler-dependent; the five tested delays provide direct regression evidence but cannot exhaust every interleaving.
- The previously accepted 162 lifetime/allocation/WeakMap/scheduler tests and 14 GC tests were not rerun in this narrow follow-up.
- The unexplained 180-second whole-bootstrap fork-under-GC-stress timeout remains unresolved. The successful fresh-process and targeted bootstrap fork probes do not prove that broader timeout is fixed.
- This verdict covers only the targeted GC/WeakMap fixes and this final concurrent-disable correction, not the repository as a whole.

**Merge verdict: OK with notes**