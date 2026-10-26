# Independent review: Fil-C metaclass publication fix

## Scope and baseline

- Reviewed `/tmp/ruby-filc/port/metaclass-publication.patch` against HEAD `e68cce301e92225de8025d60770a9d5433790fb4`.
- The live `class.c` diff byte-matches the authoritative patch and has blob hash `34f7f380dc58b0ebd9522db33cd0a328ad597f1d`.
- The patch adds eight lines only around `make_metaclass`; the additional tracked generated-file changes and build artifacts in the working tree were excluded from this review.
- This is a bounded review of the glibc/pthread Fil-C target, not an all-port or call-cache verdict.
- Per instruction, I did not compile, execute tests, run containers, or modify files.

## Findings

No issues found.

- P0: none.
- P1: none.
- P2: none.

## Correctness assessment

### Publication is covered for the complete `Qundef` interval

`class_boot_boxable(Qundef, ...)` creates the new metaclass with `RCLASS_SUPER == Qundef` at `class.c:1316`, through `class_boot_boxable` and `class_associate_super` at `class.c:784-797` and `class.c:744-760`. The metaclass first becomes reachable from its attached class at `class.c:1322` or `class.c:1327`; its real superclass is installed at `class.c:1331-1334`.

The new barrier starts before allocation at `class.c:1310-1313` and remains active through superclass association, initialization, and ancestry-cache completion, ending only at `class.c:1338-1339`. Therefore the full interval during which the published metaclass can still have a `Qundef` superclass is inside the Ractor barrier.

On the target pthread scheduler:

- `rb_vm_barrier` requires the VM lock and starts a scheduler barrier unless the current Ractor already owns one (`vm_sync.c:253-277`).
- Barrier startup interrupts all other running Ractors and waits for them to join (`thread_pthread.c:1448-1487`).
- Although the barrier serial is advanced at `thread_pthread.c:1491-1494`, the owner deliberately retains the Ractor scheduler lock through the protected operation (`thread_pthread.c:1496-1503`).
- Waiting or newly runnable threads cannot reacquire that scheduler lock until `rb_ractor_sched_barrier_end` releases it (`thread_pthread.c:1506-1518`).
- Barrier end is tied to leaving the exact recursive VM-lock level at which it was acquired (`vm_sync.c:120-143`).

Thus no other running, newly resumed, or newly started Ractor can execute Ruby object or method lookup against the partially initialized metaclass.

### Recursive `ENSURE_EIGENCLASS` is safe

`make_metaclass` recursively calls `ENSURE_EIGENCLASS` while assigning the metaclass’s class and superclass (`class.c:1326-1333`). Recursive calls:

1. recursively enter the VM lock;
2. see that the current Ractor already owns the barrier and return from `rb_vm_barrier` without trying to start another barrier (`vm_sync.c:243-272`);
3. leave only their added lock level.

Because `barrier_lock_rec` records the level that originally acquired the barrier (`thread_pthread.c:1463-1465`), a nested leave does not prematurely end it. The outer `make_metaclass` leave ends the barrier only after all recursive eigenclass construction and ancestry updates are complete.

The same reasoning applies to `singleton_class_of`, which may already hold a VM lock for a shareable object at `class.c:2821-2839`.

### Already-held barriers and locks do not deadlock

The reviewed combinations are balanced:

- **Existing VM lock, no barrier:** `make_metaclass` adds one recursive level, acquires a barrier at that new level, and ends it when leaving that level while preserving the caller’s outer lock.
- **Existing barrier:** the additional lock level is recursive and `rb_vm_barrier` is a no-op for the barrier-owning Ractor. The added leave does not end the caller’s lower-level barrier.
- **Nested normal or no-barrier locks during allocation/list maintenance:** their higher recursive levels do not match `barrier_lock_rec`, so they cannot end the active barrier. The matching normal leave at `class.c:1339` does.
- **Ractors arriving while a barrier is being established:** VM-lock acquisition detects the waiting barrier and joins it before proceeding (`vm_sync.c:91-106`).

No lock-order reversal was found in the metaclass path.

### Startup remains safe

The main Ractor is allocated and assigned to `ruby_single_main_ractor` before class hierarchy initialization (`ractor.c:468-481`). In single-Ractor mode, both VM-lock enter/leave and `rb_vm_barrier` are no-ops (`vm_sync.h:42-53`, `vm_sync.h:74-107`, `vm_sync.c:258-260`).

Consequently the bootstrap `ENSURE_EIGENCLASS(rb_cRefinement)` at `class.c:1453-1478` follows its existing recursive behavior without requiring initialized scheduler barrier state. The uninitialized local lock level is not consumed while single-Ractor mode remains active. Transition to multi-Ractor mode occurs synchronously during Ractor insertion (`ractor.c:389-423`) and cannot occur from inside this callback-free bootstrap path.

Once multi-Ractor mode has been activated, it remains the synchronization mode even if the count later falls to one, so there is no true-to-false mode transition between a matching enter and leave.

### Exception and non-local-exit behavior

VM tags record the recursive lock depth (`eval_intern.h:98-105`). A Ruby non-local exit crossing a tag checks that depth and releases extra recursive levels (`eval_intern.h:131-148`, `vm_sync.c:281-298`). Such release uses normal VM-lock leaves, so it also ends an active barrier at the recorded barrier level. The added raw enter/leave therefore does not strand the VM lock or scheduler barrier during ordinary Ruby unwinding.

There is no supported, catchable raising operation after publication in the normal `make_metaclass` path:

- The post-publication operations are valid-input eigenclass construction, subclass-list maintenance, flags, and ancestry-array construction.
- Allocation failure while the extra VM-lock depth differs from the surrounding tag is deliberately fatal rather than a resumable `NoMemoryError` (`gc.c:5170-5195`), so it cannot resume another Ractor against a partial object.
- Internal `NEWOBJ` callbacks are specified not to call Ruby APIs or create objects (`include/ruby/debug.h`, TracePoint API documentation). The standard allocation tracer performs internal bookkeeping; an extension violating that internal-event contract is outside the supported path.

The code does not roll back an already-published metaclass after an arbitrary unsupported C-level long jump, but no supported exception path was found that makes that state observable. This is not a remaining gap for the reviewed fix.

### Collector and allocation interactions

Fil-C object allocation and optional stress collection occur inside `rb_gc_impl_new_obj` (`gc/filc/filc.c:451-482`), while C-buffer allocations can also invoke stress collection (`gc/filc/filc.c:510-529`). These operations do not release the Ruby Ractor barrier. Finalizers are scheduled as postponed jobs rather than run inline during allocation.

The new metaclass is rooted by the current stack before publication and by the attached class afterward. A concurrent collector may internally observe `Qundef`, which is a valid immediate value, but it does not perform Ruby method lookup and is not an observing Ractor. No registry/VM-lock inversion was found in this path.

The supplied forced-concurrent-GC subclass test passing after the change provides practical support that allocation and collector activity under this barrier do not deadlock.

### Relevant call sites

All Class-object metaclass constructors pass through the protected function:

- `rb_make_metaclass` dispatches `T_CLASS` to `make_metaclass` (`class.c:1493-1500`).
- Ruby `Class#initialize` sets the real superclass and then calls `rb_make_metaclass` (`object.c:2157-2177`).
- Internal class-definition and Struct paths call the same API (`class.c:1503-1512`, `struct.c:251-259`).
- Public singleton-class exposure uses an outer lock for shareable objects and then the same protected Class branch (`class.c:2792-2842`).
- Recursive internal construction uses `ENSURE_EIGENCLASS` (`class.c:1283-1295`).

The non-Class `make_singleton_class` branch does not construct an object with a temporary `Qundef` superclass and is outside this specific race.

## Validation evidence reviewed

The available artifacts are consistent with the static analysis:

- Before the fix: statuses `0, 133, 133`; the inspected crash log reaches method lookup through an invalid/null class path, matching observation of incomplete metaclass ancestry.
- After the fix: five consecutive statuses are all `0`; one inspected run reports `385029` observations and `4000` retained new subclasses.
- Stock Linux Ruby 4.0.7 passes the reproducer.
- `btest`: `2044` tests passed.
- Class/module/refinement/Ractor regressions: `392` tests, `12793` assertions, no failures, errors, or skips.
- Concurrent subclass/forced-GC artifact reports all `10000` and `18000` live subclasses retained.
- The supplied prior-commit control establishes that the race also occurred on `74beca5`; nothing in this review attributes it solely to the independently reviewed weak-callcache change.

## Limitations and non-blocking notes

- I did not independently execute the validation, as required by the task.
- No allocation-failure or unsupported internal-hook fault injection is represented in the supplied tests.
- The global barrier cost of metaclass creation under multiple Ractors was not benchmarked. This is a performance consideration, not a demonstrated correctness regression.
- Conclusions about barrier lifetime rely on the target’s pthread implementation; this is intentionally not an all-platform verdict.

Merge verdict: OK