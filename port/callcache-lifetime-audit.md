# Call-cache lifetime audit

The source audit began at `74beca5` during a Docker outage. Docker recovered without a restart. The weak receiver-class correction is committed in `e68cce3` and included in both exported patches and the local images. This is not a complete implementation of all weak VM structures or proof of leak freedom.

## Original mismatch and implemented correction

At `74beca5`, `vm_callinfo.h` described `rb_callcache.klass` as weak but initialized it as an ordinary pointer-valued VALUE through `SHAREABLE_IMEMO_NEW`. Fil-C traced that capability regardless of Ruby's marking rules. VM-wide cache slots retained cache objects independently of their receivers.

`e68cce3` stores a `zweak *` in a heap cache's class field. `vm_cc_klass` atomically reads the field and resolves the weak cell; a dead target yields Qundef. Invalidation uses an atomic pointer store. Unmarkable stack/static caches retain a direct class. Both heap-to-stack conversion paths resolve the weak representation before setting the unmarkable flag. ObjectSpace dumps and debug diagnostics resolve the class rather than treating the weak cell as a Ruby object.

The intended rules in `imemo.c` remain relevant:

- The receiver class is weak.
- Normal call-cache method entries are weak; the class and its cache table keep applicable method entries alive.
- Valid super/refinement caches retain their method entries, which may otherwise be reachable only through the cache.
- Invalidated caches should not mark any fields.

At `e68cce3`, only the receiver-class representation had been corrected; `cme_` remained traced and could retain its owner/defined class. Ruby marking rules alone do not implement native weak references. The normal-CME correction below is now committed as `78e4bb7` and included in the images. Strong invalidated super/refinement fields remain separate work.

## Adjacent tables still needing treatment

`cc_refinement_table` in `vm_method.c` stores cache pointers directly, although the default collector treats its entries as weak. Invalidation must still find every live refinement cache after a refinement changes. Dropping the table would break that requirement.

`overloaded_cme_table` also uses direct pointer keys and values. The default collector treats keys as weak, but `vm.c` intentionally marks values. Do not blindly weaken both sides. Reproduce an overloaded-method lifetime before choosing its representation.

## Lifetime probe and control correction

`tcallcache-lifetime.rb` creates 500 anonymous String subclasses in either baseline mode or dispatch mode, where each instance must return the expected byte from `getbyte`. It strongly retains ten classes and watches all 500 with ObjectSpace::WeakMap. After one explicit full/immediate collection, it requires all ten held classes and no others to remain.

The original direct-frame probe passed on host stock Ruby 4.0.5 ARM64 Darwin. It retained 432 classes on old Fil-C and eleven on the first weak-class candidate. Contrary to an earlier report, the stock Ruby 4.0.7 Linux direct-frame dispatch control also retained eleven. A completed-thread variant retained ten on stock Linux but eleven on Fil-C. Heap diagnostics identified the final receiver/class; the separate residual/thread lifetime is not fully explained.

The final probe retires the allocation frame by running it in a completed Fiber. It keeps the same one-collection and exact-ten assertions. Both modes pass on stock Ruby 4.0.7 Linux and the patched port; the old `74beca5` image still retains hundreds after dispatch. Logs: `ta/callcache-fiber-{baseline,dispatch}-{filc,stock}.*` and `ta/callcache-fiber-dispatch-before-image.*`. Earlier controls remain under `ta/callcache-lifetime-*` and `ta/callcache-thread-*`.

```fish
docker exec ruby-filc-glibc /work/ruby-4.0.7-glibc/miniruby /work/tcallcache-lifetime.rb baseline
docker exec ruby-filc-glibc /work/ruby-4.0.7-glibc/miniruby /work/tcallcache-lifetime.rb dispatch
```

## Class-owned method entries: correction in 78e4bb7

`tcallcache-cme-lifetime.rb` gives each of the 500 subclasses its own Ruby method, then optionally dispatches through it. It uses the same completed-Fiber allocation boundary, ten held classes, and one explicit full/immediate collection. With the source now committed as `70c5604`, baseline retains exactly ten classes on both Fil-C and stock Ruby 4.0.7 Linux. Dispatch retains eleven on Fil-C, exit 1, versus ten on stock, exit 0. Logs: `ta/callcache-cme-{baseline,dispatch}-{filc,stock}.*`.

The follow-up `tcallcache-cme-isolate.rb` retains one or eight independent call sites. Fil-C retains one extra class per live site; redispatching those sites on a held class removes all extras. Stock retains only the controls in every case. A native heap dump then identifies eight paths from the held Proc array through ISeq storage, a callcache, its ordinary method-entry pointer and the otherwise unreachable class. The Ruby dump confirms the callcache -> ment -> CLASS types. See `ta/callcache-cme-heap-{paths,annotated}.txt` and `ta/callcache-cme-objects.jsonl`.

The original candidate changed vm_callinfo.h and vm_insnhelper.c (+24/-4), frozen in `port/weak-normal-cme.patch`. Only normal heap-cache CMEs become weak. Super/refinement and unmarkable CMEs remain direct; both stack-copy paths resolve the representation. The allocator guards the original CME, and root-cache validity checking holds the resolved class through the CME check. No strong invalidated-cache fields or adjacent tables are changed.

Independent review BLOCKED that version: a TracePoint C-call hook can remove an attr/Struct method and collect its CME before the active operation and C-return event. The lifetime probes and full test-all did not cover this reentrancy. Stock passes the eight removal variants; normal Fil-C traps in the four public_send variants, and checked Fil-C traps in all eight. See `port/independent-review-weak-normal-cme.md` and `ta/cme-trace-before-*`.

The revised five-file correction passes a resolved CME through attr/Struct operations and event metadata, guarding it through the return hook. It also preserves the active entry across Warning.warn during Ruby argument setup, including keyword/arity handling and tailcalls. That second path had a reproducible checked-build invalid-cache assertion. Cache eligibility no longer rereads an invalid CME, and it rejects an invalidated cache. Checks remain enabled. Frozen patch: `port/weak-normal-cme-final.patch`, +143/-98, SHA256 `3a541bc07270b837f293c53c45d38396aa6f60c099047fdd8868b433a1cb7098`.

All original exact-ten/one-GC lifetime and isolation checks still pass on stock, normal and checked builds, along with protected dispatch and four-Ractor invalidation. Sixteen TracePoint removal/replacement cases and seven actual warning-hook variants pass on each build; forwarding is a separate no-warning control. Normal and checked bootstrap each pass 2044 tests, and all 1577 C-API examples pass. The revised 1100-test focused selection includes leak names and has four known memory-ratio failures, no errors; full specs retain one signal failure and ten GC::Profiler errors. Logs and exact counts are in `port/STATUS.md`.

The original two-file candidate completed full test-all (34 failures, 17 errors, one new OOM kill). The revised five-file candidate also completed full test-all with leak names enabled: 33362 tests, 33 failures, 17 errors, one new OOM kill, seven descriptor warnings and no Fil-C safety errors in the complete log. No failure identities were added versus the two-file run; one variable Ripper memory ratio passed. These results do not establish general runtime correctness or resource safety. See `ta/test-all-cme-reentrancy.*` and `ta/cme-reentrancy-failure-comparison.txt`.

Follow-up review run `1265f793-dd99-440b-97c0-b02df2875e2e` failed with a provider content flag and produced no verdict. The same-model retry `d2941e04-9ba1-46e3-a1fa-976219f28691` verified the frozen diff and found no issues, returning OK with notes: `port/independent-review-weak-normal-cme-final.md`. The prior provider failure remains recorded separately. The fix is committed as `78e4bb7`, exported, and included in freshly built local images.

The 78e4bb7 clean runtime passes the expanded packaged regressions, GC checks and fresh nio4r/Puma probes. Clean bootstrap passes 2044 tests; full test-all has 32 failures and 17 errors; specs have one failure and ten errors. The clean run has three descriptor warnings and no OOM kill, while the preceding same-source worktree run had one OOM kill. These outcomes remain incomplete runtime-correctness evidence. Separately, a fresh coherent newer-toolchain build now includes the shared runtime and extensions, and passes bootstrap, optional C-API specs, lifetime/reentrancy probes and fresh nio4r/Puma checks. It lowers peak RSS in a controlled Ractor comparison, but its full test-all run still has 34 failures, 17 errors and an OOM kill. Full application and long-running coverage remain outstanding.

## Independent review and validation

The first review found an encoded weak cell copied into an unmarkable protected-call cache, and heap dumps reporting weak-cell addresses as receiver classes. Both were fixed. The dump probe fails before the correction and passes afterward. A separate VM_CHECK_MODE=1 build with only the protected-copy correction removed traps on special(weak), exit 133; restoring the correction passes. No checking was disabled.

The checked build also required numeric debug flag/signature fixes and proper Ractor ownership metadata in the per-object tail. The final nine-file review found no issues: `port/independent-review-weak-callcache-final.md`. The parent completed all 2044 checked bootstrap tests afterward. The build directory remains inside the Linux container, although the reviewer could not access that path from the host.

Focused normal tests passed 980 cases and 21296 assertions, with three skips. The complete test-all run had 33345 tests, 33 failures and 17 errors; final-source specs had 33763 examples, one failure and ten errors. These existing port failures remain. A bounded Struct comparison showed lower settled RSS but does not prove one-collection parity or general leak freedom.

Fresh `e68cce3` image checks passed weak-class lifetime, dump and protected dispatch, then exposed a separate concurrent metaclass-publication trap. It also reproduces on the older `74beca5` image. The reviewed correction is committed and included in the `70c5604` images; both concurrency probes pass there. Full suites still fail and include an OOM kill and descriptor warnings. Details are in `port/STATUS.md`; this cache review is not evidence that the full runtime is safe or complete.
