# Ruby 4.0.7 Fil-C port investigation history

## Recovery update

The temporary workspace disappeared. The port, VM-stack candidate, build example and investigation text have been recovered into `~/src/tries/2026-10-27-ruby-filc`. The consolidated and incremental patch hashes match their originals. The restored source has new local Git history; the candidate is committed on its own development branch but still lacks full-suite acceptance. See [current status](../README.md) and [recovery evidence](../RECOVERY.md).

The remainder of this file is the pre-recovery investigation record. Its old commit IDs, `/tmp` locations, running-container descriptions, publication statements and log paths describe that earlier state. Most raw logs did not survive; historical reported passes must not be mistaken for newly rerun checks or available evidence files. Public source-repository publication has now been authorized. The overall Ruby/Fil-C goal remains incomplete.

## Pre-recovery record

Worktree: `/tmp/ruby-filc/ruby-4.0.7-glibc`, latest committed source `78e4bb7` (normal-call-cache method-entry lifetime and reentrant dispatch). Exported patches and local runtime/build/application images agree at this revision. An uncommitted three-file VM-stack-retirement candidate is now built into the newer-toolchain installation and checked miniruby, but is not accepted or exported. See `port/vm-stack-retirement.md`.
Container: `ruby-filc-glibc`, `/tmp/ruby-filc` mounted at `/work`, optfil 0.686, glibc, ucontext, 8 GiB cap.

Complete compatibility has NOT been achieved. The Docker example and local ARM64 runtime/build/application images contain `78e4bb7`, including the reviewed method-entry and metaclass fixes. Clean concurrency/runtime/native-gem/application checks pass. Complete clean suites still report 32 test-all failures and 17 errors, plus one spec failure and ten errors. The latest clean run has three descriptor warnings and no OOM kill; the preceding worktree run of the same source changes had an OOM kill. Memory/resource problems remain unresolved. Nothing has been published.

Current runtime image: `sha256:5d954fbe199dfdbec305c553675b8e1d00e56e6322058506c947ba60d06ed035`, tagged `ruby-filc:4.0.7` and `ruby-filc:4.0.7-78e4bb7`. Build image: `sha256:dc0ee132e99224e4a0b187ca33fc9171ec81696eef1b366bd8ef357ae028b0ea`. Application image: `sha256:3b6eb829e3eed5ef38d5b99edef3158dd8648e0c80360ec6fa4c3c2678ea0716`. Ruby retains upstream release revision `229531a6cf`; the applied patch identifies the port. These images still use released optfil 0.686. Installed `/opt/ruby-filc` in the development container remains through `e267785`.

The earlier Docker outage recovered without a restart. After three blocked turns the user approved recovery, but Docker and the shared services were already responsive before any action. The interrupted `74beca5` test-all/spec commands eventually recorded exit 124, without complete results. Separate recovery runs completed and remain red; their results are below. The outage's last dispatched test is not established as its cause.

## Upstream reporting boundary

The user permits additional short Fil-C bug reports with minimal reproductions, following existing issues #339 and #340. Do not submit feature requests or requests for larger upstream changes. If completion requires new Fil-C capabilities, stop and discuss that dependency with the user or continue another workstream that does not require it. This is not approval to undertake a broader Fil-C runtime redesign.

## Latest progress

### Metaclass publication during concurrent construction

The new `e68cce3` image passed the cache probes but trapped during concurrent subclass insertion: method lookup reached a metaclass superclass of Qundef. The worktree reproduced it, and a three-run control on `74beca5` passed twice then trapped with the same stack. Earlier passing subclass probes did not establish absence of this separate race. Logs: `ta/image-runtime-e68cce3.*`, `ta/subclasses-weak-callcache-worktree.*`, `ta/subclasses-74beca5-control.*`.

`make_metaclass` publishes a metaclass before finishing its superclass chain. `70c5604` adds eight Fil-C-only lines holding Ruby's existing VM lock and barrier throughout construction. This prevents other Ractors from observing the intermediate state and covers recursive eigenclass construction; the non-Fil-C preprocessor branch is unchanged. The independent review found no issues: `port/independent-review-metaclass-publication.md`. Incremental patch: `port/metaclass-publication.patch`.

- `probes/ruby/metaclass-publication.rb` checks hashing, real-class identity, singleton ancestry, and retention of 4000 concurrently created subclasses. Before: statuses 0, 133, 133. Stock Ruby 4.0.7 Linux: 0. After: five fresh processes pass. `ta/metaclass-publication-{before,after}-*`, `ta/metaclass-publication-stock.*`.
- The original concurrent-GC/insertion probe now retains all 18000 held classes: `ta/subclasses-metaclass-fixed.*`.
- Bootstrap: 2044 passed, 127.08 seconds. Class/module/refinement/Ractor selection: 392 tests, 12793 assertions, no failures/errors/skips, 36.17 seconds. `ta/btest-metaclass-publication.*`, `ta/metaclass-publication-regressions.*`.
- Both standalone concurrency probes also pass after rebuilding the separate VM_CHECK_MODE=1 miniruby with this fix: `ta/vmcheck-metaclass-publication.*`, `ta/vmcheck-subclasses-metaclass.*`. Its complete bootstrap passes 2044 tests in 149.80 seconds: `ta/btest-metaclass-vmcheck.*`. The build directory is inside the Linux container, not the macOS host.
- An ordinary GCC checked-build control failed before linking because the initial port commit `ba8cb0f` unconditionally includes stdfil.h in vm_core.h. No shim was added, and there is no whole-port GCC compatibility verdict. `ta/build-native-checked.*`; helper `port/build-native-check.sh`. The metaclass change itself is Fil-C-conditional.
- The global barrier's multi-Ractor performance cost has not been benchmarked. The reviewer identified this as an unmeasured performance consideration, not a demonstrated correctness defect.

### Normal call-cache method-entry retention: candidate fix

`probes/ruby/callcache-cme-lifetime.rb` creates 500 subclasses with an owned Ruby method in a completed Fiber and performs one explicit full/immediate GC. Before the candidate, baseline retains exactly ten held classes on both Fil-C and stock Ruby 4.0.7 Linux; dispatch retains eleven on Fil-C versus ten on stock. Logs: `ta/callcache-cme-{baseline,dispatch}-{filc,stock}.*`.

`probes/ruby/callcache-cme-isolate.rb` separates live call-site retention from allocation-frame residue. One retained site keeps one extra class; eight sites keep eight. Redispatching those sites on an intentionally held class removes all extras. Stock passes every variant. A native heap dump identifies eight root paths through the retained Proc array, ISeq, call cache, ordinary method-entry pointer and class. The annotation matches Ruby dump types callcache, ment and CLASS. Evidence: `ta/callcache-cme-isolate-*`, `ta/callcache-cme-heap-probe.*`, `ta/callcache-cme-heap-{paths,annotated}.txt`, and `ta/callcache-cme-objects.jsonl`.

The original two-file candidate stores normal heap-cache method entries in zweak cells, resolves them in vm_cc_cme, guards the original entry during allocation, and pins the class during VM root-cache validity checks. Super/refinement and unmarkable caches retain direct method entries. Both stack-copy sites resolve the representation. It does not change strong invalidated super/refinement fields, the refinement table or overloaded-entry table. Original frozen patch: `port/weak-normal-cme.patch`, +24/-4. Independent review BLOCKED that version on an active-call lifetime defect; see below.

- Baseline/dispatch lifetime tests pass, including invoking every held class's method after GC. All keep/replace/release isolation variants at one and eight sites now retain exactly ten classes. `ta/callcache-cme-*-after.*`, `ta/callcache-cme-isolate-after-*`, `ta/callcache-cme-held-methods-after.*`.
- 25 redefinitions, alias updates and method removals across four Ractors with forced collections pass on stock, normal Fil-C and the checked Fil-C build. `probes/ruby/callcache-cme-invalidation.rb`; `ta/callcache-cme-invalidation-*`, `ta/vmcheck-weak-normal-cme-*`.
- Normal bootstrap: 2044 passed in 125.66 seconds. VM-check bootstrap: 2044 passed in 152.44 seconds. The checked lifetime/protected-call/invalidation probes also pass. `ta/btest-weak-normal-cme*`.
- Method/module/refinement/super/alias/proc/fiber/thread/ObjectSpace selection: 788 tests, 81350 assertions, three existing ObjectSpace failures (wb_protected, age, full-dump free slots), no errors, five skips. This selection retains the default leak-name exclusion. `ta/weak-normal-cme-regressions.*`.
- Full specs: 33763 examples, 155976 expectations, one unsupported-signal failure and ten missing-GC::Profiler errors, 210.83 seconds, exit 2. Separate C-API specs: 1577 examples, 2732 expectations, no failures/errors, 3.44 seconds, exit 0. No Fil-C safety errors in these logs. `ta/test-spec-weak-normal-cme.*`, `ta/capi-spec-weak-normal-cme.*`.
- The original two-file candidate subsequently completed test-all with leak names enabled: 33369 tests, 7244871 assertions, 34 failures, 17 errors, 208 skips, 806.26 seconds, exit 2. No Fil-C safety errors appeared in that log, but there were five descriptor warnings and a Ractor-port SIGKILL. Cgroup counters changed from oom=84/oom_kill=11 to 85/12 during this run. This is evidence of one new OOM kill, not merely historical absolute counters. `ta/test-all-weak-normal-cme.*`, `ta/memory-events-weak-normal-cme-{before,after}.log`.

#### Reentrant dispatch corrections after review

`port/independent-review-weak-normal-cme.md` found a P1: a synthetic C-call TracePoint can remove an attr/Struct method and collect its weak CME while that active call still needs it. Stock passed all eight removal cases. The two-file candidate trapped in all four public_send cases on normal Fil-C and all eight cases on VM_CHECK_MODE=1. Some normal direct calls passed because the entry remained live, but they still reread an invalidated cache. Evidence: `probes/ruby/callcache-cme-trace.rb`, `ta/cme-trace-before-*`.

The revised code passes a resolved CME to attr/Struct helpers and event metadata, with an RB_GC_GUARD through the return hook. Fast-path handlers retain their original callable signatures. The equivalent vm_call0_body paths capture the entry on each retry; they do not reread an invalid cache after the hook.

A separate Warning.warn reproduction removes the active Ruby method and runs GC before its frame is created. Stock and normal Fil-C passed, but the checked candidate asserted on an invalidated cache. The fix carries the resolved CME through argument setup, keyword/error handling and normal/tail frame creation, rather than rereading the cache after the warning. Cache eligibility checks reject invalidated caches. No VM checks were disabled. Evidence: `probes/ruby/callcache-cme-warning.rb`, `ta/cme-warning-before-*`; the first attempt's nonexistent warning-category error is preserved under `*-invalid-category.*`.

Frozen incremental patch: `port/weak-normal-cme-final.patch`, five files, +143/-98, SHA256 `3a541bc07270b837f293c53c45d38396aa6f60c099047fdd8868b433a1cb7098`. Follow-up review run `1265f793-dd99-440b-97c0-b02df2875e2e` failed with a provider cybersecurity-content flag, without an artifact or verdict. The single same-model retry `d2941e04-9ba1-46e3-a1fa-976219f28691` completed, verified the exact diff and found no issues, returning OK with notes. No model/access settings were changed. Records: `port/independent-review-weak-normal-cme-final-provider-failure.md` and `port/independent-review-weak-normal-cme-final.md`. The accepted fix is committed as `78e4bb7`, exported and included in the local images. The bounded review notes that warning callbacks combined with alias chains or inherited-tree invalidation were not separate standalone cases; broader alias/invalidation coverage passed.

- All 16 TracePoint removal/replacement combinations pass on stock, normal and checked builds: attr/Struct, reader/writer, direct/public_send. Event identity, current operation and subsequent method visibility/replacement are checked. `ta/cme-final-trace-*`.
- Seven warning-hook paths pass on all three builds: simple, optional, explicit/default keyword, complex, tailcall and arity error. The tailcall probe verifies a TAILCALL instruction. Forwarding is a no-warning control, not a warning-callback test; stock also emits no warning for an unused forwarded block. The initial incorrect forwarding expectation remains in `ta/cme-warning-after-*-forwarding.*`; corrected controls are in `ta/cme-final-warning-*`.
- Original exact-ten/one-GC lifetime checks, all six isolation variants, four-Ractor invalidation and protected dispatch also pass on all three builds. `ta/cme-final-{lifetime,isolate,invalidation,protected}-*`.
- Normal and checked bootstrap each pass 2044 tests, in 151.65 and 178.86 seconds. `ta/btest-cme-reentrancy{,-vmcheck}.*`.
- Focused method/class/module/Struct/refinement/optimization/keyword/TracePoint/alias/iterator/super/proc selection, including leak names: 1100 tests, 20605 assertions, four memory-ratio failures, no errors, three skips, 77.52 seconds. Failures are TracePoint, class extension, complemented method entry and iclass, all previously observed failure identities. `ta/cme-reentrancy-regressions.*`.
- Full specs: 33763 examples, 155136 expectations, one signal failure and ten GC::Profiler errors, 223.60 seconds. C-API: 1577 examples, 2732 expectations, no failures/errors, 3.73 seconds. No Fil-C safety error appears in these three suite logs. `ta/cme-reentrancy-{regressions,spec,capi}.*`.
- Driver: `port/validate-weak-cme-reentrancy.sh`; overall exit 1 because it preserves the failing Ruby-suite statuses.
- The revised five-file candidate then completed full test-all, including leak names: 33362 tests, 7248609 assertions, 33 failures, 17 errors, 208 skips, 849.27 seconds, exit 2. The live diff still matched the frozen patch. There are no added failure identities versus the original two-file candidate; Ripper's warn-callback memory ratio passed this time. Versus the 70c5604 image, iclass memory growth returned while Rational GCD and Ripper warn-callback ratios passed. These variable ratios do not establish fixes. `ta/test-all-cme-reentrancy.*`, `ta/cme-reentrancy-failure-comparison.txt`; comparison helper `port/compare-suite-failures.py` normalizes test identities across source paths.
- This complete log has no Fil-C safety error, but has seven descriptor warnings and a Ractor-port SIGKILL. During this test-all run, cgroup max events rose 143708 to 145017, oom 85 to 86, and oom_kill 12 to 13: one additional OOM kill. `ta/memory-events-cme-reentrancy-{before,after}.log`.
- Clean-source image validation subsequently completed for `78e4bb7`; see below. The standalone CME lifetime, isolation, reentrancy and invalidation checks are now copied into `example/regressions/` and run by `example/regressions.sh`.

### Weak call-cache classes and checked builds

`e68cce3` stores heap call-cache classes in weak cells, resolves them through `vm_cc_klass`, and uses atomic reads/invalidation. Stack/static unmarkable caches retain direct classes. Both heap-to-stack conversion paths resolve that representation before setting the unmarkable flag. ObjectSpace dumps resolve the class once and report actual Ruby class addresses rather than weak-cell addresses. Normal CME and adjacent weak-table semantics remain separate work; see `port/callcache-lifetime-audit.md`.

- The final lifetime probe retires its allocation frame in a completed Fiber, then requires exactly ten held classes after one full/immediate collection. It passes on stock Ruby 4.0.7 Linux and the patched port; the old image retains hundreds. The earlier direct-frame Linux control retained eleven, not ten; the initial claim that it passed was incorrect. Thread/direct-frame residual retention remains unexplained. Logs: `ta/callcache-fiber-{baseline,dispatch}-{filc,stock}.*`, `ta/callcache-fiber-dispatch-before-image.*`.
- Independent review found and prompted corrections to the protected-call stack copy and ObjectSpace dump. A VM-check build without only the protected-copy correction traps on special(weak), exit 133; restoring it passes. Final nine-file review found no issues: `port/independent-review-weak-callcache-final.md`. This is a bounded review, not an all-port verdict.
- The checked build fixes numeric flag/signature operations and initializes Ractor ownership in the aligned per-object tail; it does not disable checks. Its full bootstrap passes 2044 tests in 167.39 seconds: `ta/btest-weak-callcache-vmcheck.*`. The review's build-path limitation was host/container visibility; the parent subsequently accessed and rebuilt that Linux directory.
- Focused normal selection: 980 tests, 21296 assertions, no failures/errors, 3 skips. Full test-all including leak names, before the final debug-only additions: 33345 tests, 7244616 assertions, 33 failures, 17 errors, 208 skips, 825.34 seconds. Final-source specs: 33763 examples, 156128 expectations, 1 failure, 10 errors, 220.42 seconds. Both full logs have no Fil-C safety errors, but the later concurrency probe does. Logs: `ta/weak-callcache-class-regressions-corrected.*`, `ta/test-all-weak-callcache-class.*`, `ta/test-spec-weak-callcache-final.*`.

### Independent review and concurrent GC fixes

The Daybreak Blue latest xhigh review found three defects in `bc4a436`: explicit collection overwrote concurrent GC.enable state, GC.count exposed automatic native cycles while Ruby GC was disabled, and WeakMap omitted two pointer fields per entry from its memory accounting. A follow-up caught premature root restoration when GC.disable overlapped a pending explicit collection. All four were reproduced and corrected in `19f520d`.

- Logical GC state is separate from temporary release of retained roots. Pending explicit requests prevent bulk restoration until the last request finishes. New objects allocated after disabling remain individually retained.
- Public enable/disable transitions and their previous-state return values are serialized. Ruby-visible counts use actual completed cycle numbers, excluding automatic implementation cycles during disable while counting explicit requests. GC.stat uses one count snapshot for its related fields.
- WeakMap reports the entire C entry size. The 100-entry comparison changed from 5064/5064 bytes to 6664/5064 bytes, exactly the omitted 1600 bytes.
- The original race now returns [true, false] in six fresh processes. Disabled allocation leaves the count unchanged; explicit GC.start increases it. Overlapping requests, 160 concurrent enable/disable transitions, enable during overlap, and forked counters pass. Concurrent disable previously retained all 1000 unreachable weak keys at three tested delays; after correction, all five delays leave zero. Scripts: `probes/ruby/review-gc-state.rb`, `probes/ruby/review-disable-retention.rb`, `probes/ruby/review-weakmap-size.rb`; logs: `ta/review-*`.
- Lifetime/allocation/WeakMap/scheduler selection: 162 tests, 1784 assertions, no failures/errors, 5 skips. GC selection: 14 tests, 76 assertions, no failures/errors/skips. The existing descriptor warning remains.
- Final reviewed fixes pass all 2044 bootstrap tests in 129.28 seconds. An earlier candidate run timed out once in the fork-under-GC-stress case; five exact fresh-process probes and the five fork bootstrap tests subsequently passed. The timeout remains unexplained, not proven fixed. Logs: `ta/btest-review-fixes.log`, `ta/review-fork-*`, `ta/btest-review-fixes-final.{log,status}`.
- Complete worktree test-all at `19f520d`, WITH leak tests: 33330 tests, 7245429 assertions, 33 failures, 17 errors, 208 skips, 797.25 seconds. No safety errors. The extra failure versus the prior complete run is Ripper's warn-callback memory ratio, which has failed historically. Specs: 33763 examples, 160992 expectations, 1 failure, 10 errors, 209.57 seconds; no safety errors. Logs: `ta/test-all-review-fixes.{log,status}`, `ta/failures-review-fixes.txt`, `ta/test-spec-review-fixes.{log,status}`.
- Review artifacts: `port/independent-review-bc4a436.md`, `port/independent-review-fixes.md`, and `port/independent-review-fixes-final.md`. The final targeted review found no remaining issues. This is not an all-port compatibility verdict.

### Subclass traversal during concurrent collection

The clean image through `19f520d` exposed a Ruby BUG assertion in TestClass#test_subclass_gc_stress: the two-pass enumeration assumed GC could not complete during subclass traversal. A standalone concurrent-GC probe also aborted with exit 133. This was not a Fil-C bounds trap or an OOM. The interrupted clean test-all run has no aggregate result: `ta/image-test-all-19f520d.log`.

`74beca5` uses a single traversal with a growable result array under the existing VM lock for Fil-C. Live weak references are immediately retained in the result, linked nodes remain traced, and insertion/pruning cannot run concurrently. The non-Fil-C two-pass algorithm and its assertion remain unchanged.

- Class/module/refinement tests: 375 tests, 14036 assertions, no failures/errors/skips; `ta/subclasses-regressions.log`.
- `probes/ruby/subclasses-concurrent-gc.rb` preserves 10000 held children across 100 enumerations with concurrent collection, then 18000 children after concurrent insertion and a forced-GC traversal. Before exit 133; after exit 0. Logs: `ta/subclasses-concurrent-{before,after}.{log,status}`.
- Independent focused review found no issues and returned OK: `port/independent-review-subclasses.md`. Recovery suites later completed. The later metaclass-publication race is a separate defect and also affects this revision.

### Clean-image verification by revision

Root and example patches contain `78e4bb7` and are byte-identical: 142 files, +2815/-1192, 397861 bytes, 10540 lines, SHA256 `8f1c5499c82289007f59bb04c4507b4d0fa9780d74153737ff1c128706e47f71`. Pristine apply-check passes. Export explicitly disables external and colored diffs. The previous export remains at `port/export-through-70c5604.patch`.

- `78e4bb7` clean bootstrap: 2044 passed, 130.71 seconds. Test-all including leak names: 33352 tests, 7243418 assertions, 32 failures, 17 errors, 243 skips, 798.76 seconds. Specs: 33763 examples, 153151 expectations, one failure and ten errors, 207.48 seconds. Statuses 0, 2, 2. `ta/image-{btest,test-all,spec}-78e4bb7.*`.
- No Fil-C safety errors in the complete suite logs. Three descriptor warnings remain: ISeq GC-stress compilation, fiber-scheduler GC-stress compilation, and RubyGems PQC SSL client-cert authentication. This clean sequence recorded max=22276, oom=0, oom_kill=0 from all-zero starting counters. The Ractor-port test passed here, unlike the preceding worktree run; that variability is not evidence that memory pressure is resolved. `ta/image-memory-events-78e4bb7-{before,after}.log`.
- No added failure identities versus the reviewed worktree run; its Ractor SIGKILL is absent. Versus the 70c5604 image, iclass memory growth returned while Rational GCD, Ripper warn-callback memory growth and Ractor-port SIGKILL are absent. `ta/image-failure-comparison-78e4bb7.txt`.
- Runtime smoke/libc audit, expanded packaged regressions, GC-state/retention/accounting, mapped-buffer contract and fresh nio4r/Puma builds pass, status 0. nio4r completes 100 events on epoll/poll/select; Puma completes 100 concurrent forced-GC POSTs. Driver `port/check-runtime-image.sh`; `ta/image-runtime-78e4bb7.*`. The intentional native overflow smoke check still exits 133 as expected.
- Application HTTP and default IRB checks pass, status 0: `ta/app-checks-78e4bb7.*`. All runtime/build/app tags have been updated locally; nothing was published. Build logs: `ta/docker-build-78e4bb7.*`, `ta/docker-build-stage-78e4bb7.*`, `ta/app-build-78e4bb7.*`.

- `70c5604` bootstrap: 2044 passed, 139.81 seconds. Full test-all INCLUDING leak names: 33353 tests, 7247383 assertions, 34 failures, 17 errors, 243 skips, 763.27 seconds. Specs: 33763 examples, 156275 expectations, 1 failure, 10 errors, 203.94 seconds. Statuses are 0, 2, 2. Logs: `ta/image-{btest,test-all,spec}-70c5604.*`; driver `port/validate-clean-image.sh`.
- Neither full-suite log contains a Fil-C safety error. However, the test-all log has eight leaked-descriptor warnings and the Ractor-port subprocess was killed by SIGKILL. The container cgroup counters increased from zero to oom=2 and oom_kill=1 during the suite sequence, confirming an OOM kill occurred in this run. Logs: `ta/image-memory-events-70c5604-{before,after}.log`.
- Against the complete `74beca5` image recovery run there are no new failure names; iclass and Ripper sexp memory ratios passed this time. Against the preceding weak-cache worktree run, class-extension memory growth and the Ractor-port SIGKILL returned, while iclass passed. These variable outcomes are not proof those memory problems are fixed. Identity lists: `ta/*-failure-names.txt`.
- `70c5604` smoke/libc audit, packaged cache/concurrency regressions, all GC-state cases, WeakMap accounting, mapped-buffer contract, freshly compiled patched nio4r and unchanged Puma pass, combined status 0. `ta/image-runtime-70c5604.*`. The runtime audit remains glibc-only apart from the disclosed libc++ portability headers.
- The rebuilt application returns HTTP 200 with Ruby 4.0.7 and /opt/fil/bin/filcc; the default IRB command evaluates 1 + 1 to 2. `ta/app-checks-70c5604.status` is 0; HTTP, server and IRB artifacts share that revision. The first helper attempt contacted the mapped port before server readiness (empty reply); a second correctly exercised HTTP/IRB but expected an IRB prompt marker absent in noninteractive output. Both failed helper attempts are preserved with .before-readiness and .before-irb-assertion suffixes. The corrected helper waits for the listener and validates the actual output.
- `example/regressions.sh` packages the existing standalone lifetime, dump, protected-dispatch, metaclass-publication and concurrent-GC subclass probes under `example/regressions/`. These are executable system checks, not modified Ruby-suite assertions.

- `e68cce3` bootstrap: 2044 passed, 141.04 seconds; `ta/image-btest-e68cce3.*`.
- `e68cce3` smoke, runtime audit, weak-class lifetime, heap dump, and protected-call checks passed. The following subclass insertion probe trapped, exit 133. The shell stopped there: GC-state, mapped-buffer and fresh native-gem checks later in that command DID NOT RUN. `ta/image-runtime-e68cce3.*`. The application at that revision received no new HTTP/IRB verification. No complete test-all/spec run was performed for that image.
- `74beca5` recovery test-all including leak names: 33334 tests, 7244505 assertions, 36 failures, 17 errors, 243 skips, 810.75 seconds. Specs: 33763 examples, 160045 expectations, 1 failure, 10 errors, 210.67 seconds. Both exit 2, with no Fil-C safety errors in those complete logs. `ta/image-test-all-74beca5-recovery.*`, `ta/image-spec-74beca5-recovery.*`.
- `74beca5` bootstrap passed 2044 tests in 130.42 seconds. Its earlier smoke/audit/GC-state/mapped-buffer/subclass and freshly built nio4r/Puma probes passed, although the later repeated subclass control trapped. Historical evidence: `ta/image-btest-74beca5.*`, `ta/image-runtime-74beca5.*`.
- Audits still identify glibc and report the two libc++ musl portability headers, not a musl runtime. Native-gem results belong only to the explicitly tested revisions; these are not full gem suites or Rails validation.

### Current port with the coherent newer toolchain

A fresh pristine Ruby 4.0.7 tree was patched with the 70c5604 export plus the exact reviewed five-file patch, equivalent to committed `78e4bb7`. Every exported source and the five candidate files were compared with the worktree before building. It lives at `/compiler/ruby-current-port-RIX4Yp/ruby-4.0.7` in `ruby-filc-toolchain`; path record `ta/ruby-cme-current-toolchain-path.txt`. Source snapshot patches remain beside it. The compiler/runtime are the coherent source build at `9d1ed206e0ccfc1ec114471386befeba643a5f86`, not swapped libraries from the released toolchain. Interpreter and loaded libraries all resolve under `/compiler/source/pizfix`.

- Fresh miniruby build passes. Bootstrap: 2044 passed in 128.53 seconds. `ta/ruby-cme-current-toolchain-build.*`, `ta/btest-cme-current-toolchain.*`. Helper `port/build-current-port-toolchain.sh` now consumes the consolidated export rather than reapplying the committed incremental patch.
- CME/class lifetime, six isolation variants, 16 TracePoint cases, warning/forwarding controls, protected dispatch, four-Ractor invalidation, metaclass/subclass concurrency, six GC-state cases, five disable-retention delays and the mapped-buffer contract all pass. `ta/current-toolchain-miniruby-checks.*`, individual `ta/current-toolchain-*.status`; driver `port/check-current-toolchain-miniruby.sh`.
- Unchanged `probes/ruby/ractor-port-pressure.rb 10` was run three times with each coherent toolchain, alternating order, in the same container under 8 GiB/no swap/CPUs 0-3. Both Ruby sources contain 78e4bb7; the released-toolchain binary still prints its build-time parent revision. All six runs completed. Released peak RSS: 7532156, 8015744, 6549608 KiB; newer: 4212956, 4713624, 4833052 KiB. Elapsed times: released 8.76/8.63/8.42 seconds, newer 7.83/7.74/7.77 seconds. All six cgroup event deltas were zero. This shows lower peak memory for this workload, not general leak freedom or a resolved full-suite OOM. `ta/ractor-cme-toolchain-*`; driver `port/compare-ractor-toolchains.sh`.
- The first measurement attempt could not start because GNU time was missing, exit 127. Those files are preserved with `.before-time-install`; GNU time was installed and the driver now checks required executables before launching workloads.
- Private file-backed growth remains wrong with the newer toolchain: observed A rather than stock B, exit 1. `ta/buffer-private-file-current-toolchain.*`.
- Full shared Ruby, bundled gems and extensions now build and install against freshly compiled libffi 3.8.0, zlib 1.3.2, libyaml 0.2.5 and OpenSSL 3.6.5. Installed Ruby is `/compiler/ruby-current-port-RIX4Yp/install/bin/ruby`. All inspected loaded native libraries resolve to that Ruby installation or `/compiler/source/pizfix`, with no released optfil libraries mixed in. `ta/current-toolchain-ruby-full-build.*`, status 0. Drivers: `port/build-current-toolchain-dependencies.sh`, `port/finish-current-toolchain-ruby.sh`.
- Full-runtime bootstrap passes 2044 tests in 127.18 seconds. Test-all includes leak names and reports 33367 tests, 7245221 assertions, 34 failures, 17 errors, 201 skips, 844.43 seconds. Specs: 33763 examples, 156271 expectations, one failure/ten errors, 199.61 seconds. Optional C-API: 1577 examples, 2732 expectations, no failures/errors, 3.27 seconds. Per-suite statuses 0/2/2/0; `ta/current-toolchain-{btest-full,test-all,spec,capi}.*`.
- No Fil-C safety errors occur in those Ruby suite logs, but the Ractor-port child is killed by SIGKILL. Test-all adds cgroup max=1167, oom=5, oom_kill=1; the other suites add zero events. Three descriptor warnings remain (NetHTTP retry, scheduler GC-stress compilation, ISeq GC-stress compilation). The newer toolchain does NOT resolve the full-suite OOM. Compared with the latest released-toolchain image, the Ractor SIGKILL and Ripper warn-callback memory ratio reappear; there are no new failure identities versus the earlier two-file CME run. `ta/current-toolchain-failure-comparison.txt`, per-suite memory-event snapshots.
- The exact Ractor test run alone subsequently passes: one test/five assertions, 7.50 test seconds, process-tree maximum RSS 2973180 KiB. This is not a fix; combined/full-run memory pressure still needs per-process attribution. `ta/current-toolchain-ractor-target.*` and its memory snapshots.
- Installed-runtime smoke, HTTPS, native overflow detection, expanded packaged regressions, WeakMap accounting, mapped-buffer contract, IRB and freshly compiled nio4r/Puma probes pass, status 0. `ta/current-toolchain-runtime.*`; `port/check-current-toolchain-runtime.sh`. Gem builds use a fresh directory plus only this installation's bundled gems; no old native gem binaries are reused.
- Initial full-suite harness attempts could not find runuser because PATH omitted /usr/sbin; no tests ran. Initial runtime smoke hid the newly built bundled Fiddle gem by setting GEM_PATH to only the empty fresh gem directory. Both harness mistakes are fixed, and their original logs/statuses remain with `.before-runuser-path` / `.before-gem-path` suffixes. `example/smoke.sh` now accepts an explicit FILC_CC expectation, retaining the released compiler path as its default.
- Dependency test coverage is not fully green. The pinned Fil-C OpenSSL port removes eight recipes and skips QUIC radix. Restoring them exposed six failing recipes initially. QUIC, AFALG and shlibload pass; bioprint passes after correcting existing test vararg types without changing assertions. Four recipes explicitly trap because secure malloc is unsupported; the symbol-presence recipe still fails and needs a Fil-C ABI-aware audit. Details, source checksums and logs: `port/dependencies/README.md`. The dependency driver now includes the restored-test audit and propagates its failure.
- The Docker images above remain on released optfil at 78e4bb7. Full native-gem upstream suites, Rails, TLS/cluster workloads, amd64 and long-running stability remain outstanding. The subsequent process-memory investigation is below.

### VM-stack retirement candidate

The corrected live-key probe finds 99 strings retained after recursive Ruby calls return while their Fiber remains alive; stock Ruby 4.0.7 Linux retains zero after the same single full/immediate GC. Native heap paths identify the Fiber VM-stack allocation as the retaining object. The revised candidate clears retired frame storage, and its fresh full-runtime heap dump finds zero of the 100 watched objects reachable.

The initial one-file candidate passed normal bootstrap but was blocked in independent review on a tailcall frame-push overflow path that skipped cleanup. A separate checked-build startup trap exposed REWIND_CFP reactivating a frame slot that nested calls had reused and cleared. Both were reproduced and corrected: overflow cleanup now precedes the raise, and the Fil-C rewind macro saves/restores the hidden frame before republishing it. VM_CHECK_MODE=1 and VM_DEBUG_BP_CHECK=1 remain enabled. No diagnostic logging remains in candidate source.

Revised frozen diff: `port/vm-stack-clear-revised.patch`, vm.c/vm_core.h/vm_insnhelper.c, +83/-4, SHA256 `9147af50928511bfe5b0e6b171228324c814b59ca33c6ad9bcaf18eec37023f6`. Initial review: `port/independent-review-vm-stack-clear.md`, BLOCK; same-model follow-up `port/independent-review-vm-stack-clear-revised.md` verified this exact patch and returned OK with notes, with no concrete defects. The bounded review mission is complete, but full runtime acceptance is not. Details, negative controls, source/build identities and evidence paths are in `port/vm-stack-retirement.md`.

- Normal and checked bootstrap each pass 2044 tests (137.78/166.85 seconds), and all 50 existing standalone regressions pass in each build. The remote validation finished after its host command was interrupted; the four individual suite statuses and complete logs establish those results, not a missing outer aggregate status.
- Nine retirement scenarios plus exact lifetime, alias/undef callback and rescued tailcall-overflow probes pass on normal and checked miniruby. Held closures retain exactly their ten expected strings; tailcall tests verify compilation and argument preservation.
- Full normal runtime/extension build and install pass. The installed newer-toolchain Ruby now contains this candidate, not plain 78e4bb7. A static same-toolchain baseline miniruby has been preserved for resource comparison. Released-toolchain Docker images and both exported patches remain unchanged at 78e4bb7.
- Full test-all/spec/C-API validation is incomplete: Docker became unresponsive while test-all had dispatched 36/758 files. The host command timed out at 3430 seconds, with no per-suite result. This does not establish a Ruby deadlock or any full-suite pass/failure count. Inspect the remote job after recovery before rerunning it.

A new forwarding/tailcall cross-product control passes outgoing-only tailcalls on host stock Ruby 4.0.5, but bidirectional tailcalls raise an argument-count error on that same stock runtime. This is not yet a Fil-C finding; stock Linux 4.0.7 and baseline/candidate comparisons remain pending. Both cases and the failed initial disassembly assumption are preserved in `port/vm-stack-retirement.md`.

The source changes remain uncommitted. No OOM resolution, all-frame liveness guarantee, native-gem compatibility, or full-port correctness claim follows from these focused passes. No publication occurred.

### Parallel memory-pressure measurements and rejected experiments

`port/profile-process-memory.py` records process identities, RSS, anonymous/file memory, thread counts, and cgroup usage/events every 250 ms while preserving the child command's status. `port/summarize-process-memory.py` reports peak samples and OOM transitions. RSS totals can double-count shared pages; cgroup usage is recorded separately.

- A profiled full test-all run on unchanged 78e4bb7 with the newer toolchain, nobody/umask 022, 8 GiB/no swap/CPUs 0-3 and the same -j2 settings completed in 822.04 seconds: 33350 tests, 7244314 assertions, 34 failures, 17 errors, 201 skips, exit 2. This run had no additional OOM events, but reached 8560386048 bytes of cgroup usage, about 7.97 GiB. At that sample, the Ractor-port child used 5531416 KiB RSS, the two test workers 1181044 and 1127272 KiB, and the main runner 541172 KiB. This attributes the near-limit peak to combined pressure, not the Ractor child alone. `ta/current-toolchain-test-all-profile.{log,jsonl,status}`, `ta/current-toolchain-test-all-profile-summary.txt`.
- Two simultaneous unchanged `probes/ruby/ractor-port-pressure.rb 10` processes provide a shorter pressure reproduction. Both collector-logged and ordinary runs OOM-killed one child in roughly ten seconds. Their driver records each child's status separately. `port/concurrent-ractor-pressure.py`; `ta/concurrent-ractor-pressure-1*`, `ta/concurrent-ractor-pressure-plain-before*`. This deliberately concurrent diagnostic is not substituted for Ruby's full suite.
- `probes/c/setjmp-scavenge.c` runs four rounds of 40 pthreads, 200000 setjmp invocations per thread, then five forced collections followed by synchronous scavenging. Before scavenging, sampled RSS grows from 4039548 to 6764808 KiB across rounds; scavenging reduces it to approximately 33-35 MiB each round. It completes, exit 0. This demonstrates reclaimable committed memory, not a complete Ruby OOM fix. `ta/setjmp-scavenge-current.*`.
- An allocation-poll experiment attempted synchronous scavenging when it observed a completed automatic GC cycle. It built, but the two-process Ractor reproduction still OOM-killed a child. The experiment was reverted. Diagnostic patch `port/automatic-cycle-scavenge.patch`; `ta/current-toolchain-auto-scavenge-build.log`, `ta/concurrent-ractor-pressure-auto-scavenge-1*`.
- Current compiler assembly shows a 352-byte VM tag payload allocated for each rb_vm_exec invocation, in addition to its internal setjmp allocation. A separate one-slot native-thread cache of inactive, cleared VM tags also built but did not prevent the concurrent OOM. It was reverted without acceptance or a correctness verdict. Diagnostic patch `port/vm-tag-cache.patch`; `ta/current-toolchain-vm-tag-cache-build.*`, `ta/concurrent-ractor-pressure-tag-cache-1*`. The initial assembly command lacked Ruby include paths and failed before generating output; preserved as `ta/current-vm-assembly-before.*.before-includes`.
- Both experiments have been removed from the host source and the newer-toolchain build source. The baseline was rebuilt and reinstalled successfully, status 0: `ta/current-toolchain-pressure-experiments-revert.*`. Only the four previously generated tracked files remain modified in the host repository. Source HEAD, both exports and Docker images remain 78e4bb7; export SHA256 remains 8f1c5499c82289007f59bb04c4507b4d0fa9780d74153737ff1c128706e47f71.
- `probes/ruby/vm-stack-lifetime.rb` investigates references left in inactive Ruby VM frames while their Fiber remains alive. Its initial measurement incorrectly used WeakMap#size, which includes unpruned dead entries on stock Ruby; those direct/Fiber logs and programs are preserved under `ta/vm-stack-lifetime-*before*` and `ta/vm-stack-lifetime-direct.rb`. The corrected probe enumerates live keys, retains the one-GC/exact-zero assertion, and passes on host Ruby 4.0.5: `ta/vm-stack-lifetime-fiber-stock-darwin.*`. The corrected Linux stock 4.0.7 and Fil-C comparisons are still pending. No VM-stack-clearing change has been made, and the OOM is not attributed to this hypothesis.
- After the baseline rebuild and initial lifetime probes, Docker's API stopped responding. An exec command timed out at 30 seconds and bounded /_ping requests timed out at five seconds. The vmgr log ends in a sleep entry, which does not establish the cause. `ta/docker-health-pressure-outage.log`. The user approved recovery, but Docker was responsive again before intervention, so no restart or other disruptive recovery was performed. Work resumed and reached the VM-stack candidate above. A later full-suite attempt encountered another unresponsive-Docker incident; that interrupted validation is recorded separately in `port/vm-stack-retirement.md`.

### Mapped-buffer resizing

`bc4a436` restores the supported Fil-C remapping paths. The earlier blanket diagnosis that Fil-C lacks mremap was incorrect: release 0.686 supports shared remapping and in-place shrinking, but private relocation returns ENOSYS. `probes/c/mremap-support.c` verifies shared relocation preserves existing bytes while private relocation returns errno 38; `ta/mremap-support-release.log`.

- Mapped shrinking uses the in-place path. Shared growth uses mremap rather than copying, preserving cross-fork sharing. Only unsupported private relocation uses the existing copy fallback; that fallback now allocates a real mapped buffer with the retained mapping flags rather than silently changing to an internal buffer.
- The original fork/shrink probe now prints `mapped=true shared=true child="new!"`. An additional contract probe passes on both Fil-C and native ARM64 stock Ruby: private resizing, zero filling, shared shrink/regrowth within the original extent, and fork visibility. Logs: `ta/buffer-shared-remap.log`, `ta/buffer-remap-contract-{filc,stock}.log`.
- IO::Buffer tests: 80 tests, 707 assertions, no failures/errors, 1 skip. Buffer specs: 176 examples, 240 expectations, no failures/errors. Full specs: 33763 examples, 161588 expectations, 1 failure, 10 errors, 218.84 seconds; no Fil-C safety errors. Logs: `ta/buffer-remap-tests.log`, `ta/buffer-remap-spec.log`, `ta/test-spec-buffer-remap.log`. Remaining spec failure is unsupported signals; errors are GC::Profiler.
- Private file-backed growth is still not equivalent to mremap. In `probes/ruby/buffer-private-file.rb`, growing a mapping then modifying a still-clean original file page yields B on stock Ruby but A on both the earlier installed port and this worktree. The fallback loses file association. This is a confirmed pre-existing gap, not resolved by preserving allocation type. Logs: `ta/buffer-private-file-{before,filc,stock}.log`.

### Memory reclamation

- `446e85a` preserves old allocation sizes in Ruby's internal sized-realloc calls under Fil-C and avoids reallocating when the requested size is unchanged. Without the header change, Ruby discarded the old size and the adapter's reuse check was ineffective. The original large-string expansion test now passes: 2 tests, 7 assertions, no failures/errors/skips, `ta/string-expand-sized.log`. No workload or threshold was changed.
- The same commit calls Fil-C's documented `zscavenge_synchronously()` after an explicit full, immediate collection. Collection alone does not decommit freed pages. Separate leak coverage fell from 52 failures in 67 tests to 10 failures before the sized-realloc header fix. Logs: `ta/memory-leak-serial.log`, `ta/memory-leak-scavenge.log`.
- `5f70d87` removes dead registry entries and trims excess registry capacity before full, immediate collection. It leaves registry indices unchanged during active enumeration. The million-empty-WeakMap probe previously settled at 161316-175220 KiB after repeated collections; with trimming, later collections settle near 92700 KiB across three rounds. The first collection still leaves substantially more memory, so this does not establish immediate native cleanup or general leak freedom. Logs: `ta/weakmap-gc-{phases,trim}.log`; probe: `probes/ruby/weakmap-gc-phases.rb`.
- Latest serial leak selection: 67 tests, 417 assertions, 7 failures, no errors/skips, 337.63 seconds. Remaining cases: TracePoint, Ripper compile-error callbacks, Rational GCD, ISeq keyword loading, autoload, iclass, and empty WeakMap creation. The pre-review full parallel run had eight leak failures, with a different set; the latest complete worktree run has nine. These ratios remain variable. Logs: `ta/memory-leak-registry-trim.log`, `ta/test-all-with-leaks-registry-trim.log`.
- Lifetime/allocation/scheduler regression selection: 132 tests, 1741 assertions, no failures/errors/skips. GC stress/finalization/disable/ID selection: 14 tests, 76 assertions, no failures/errors/skips. Bootstrap: 2044 passed. The scheduler selection still emits a leaked `/dev/null` descriptor warning followed by a later close; the same warning predates these changes in `ta/scheduler-fixed-tests.log`. Do not treat a zero failure count as absence of resource warnings.

### Source-built compiler/runtime

The missing compiler source was acquired independently, pinned to `9d1ed206e0ccfc1ec114471386befeba643a5f86`. A coherent LLVM/Clang, compiler-rt, yolounwind, Fil-C runtime, glibc 2.44, libc++/libc++abi, minilute, and sarcasm build now exists in container `ruby-filc-toolchain`, volume `ruby-filc-toolchain-data`, under `/compiler/source`. Compiler: `/compiler/source/build/bin/clang`; matching libraries: `/compiler/source/pizfix`. It reports Fil-C 0.686 despite containing newer source than the released 0.686 distribution. Scripts are in `port/{prepare-toolchain.sh,populate-toolchain.py,build-toolchain.sh}`. This is not yet a replacement application/toolchain distribution.

- Controlled standalone setjmp comparison used the same container with 8 GiB RAM, no swap, and CPUs 0-3. The release binary was OOM-killed, exit 137. The source-built binary completed four separate four-round runs, all exit 0. Post-collection RSS nevertheless reached 6736392 KiB, despite roughly 34 KiB surviving in completed forced collections. This is improvement, not resolution of memory pressure. Earlier results with an additional swap allowance are not the controlled comparison. Logs: `ta/setjmp-noswap-{old,current,current-1,current-2,current-3}.{log,status}`.
- Ruby miniruby rebuilt with the matching compiler/runtime passes all 2044 bootstrap tests, 124.83 seconds. Three Ractor workload runs complete, with sampled RSS still reaching roughly 4982 MB. The named-Struct probe remains near 344000 KiB with 306 classes and two named classes. Logs: `ta/btest-current-toolchain.log`, `ta/ractor-current-toolchain-*.log`, `ta/ruby-current-toolchain-pressure.log`.
- Those source-built-toolchain Ruby results use the earlier port through `e267785`, before the memory fixes above. Full extension suites and the Docker example have not been rebuilt with this toolchain. Do not mix old-runtime native libraries into the new setjmp ABI.

The initial reviewer attempt failed at the provider safety filter and returned no findings. The user then requested Daybreak Blue latest xhigh; the successful reviews and corrections are recorded above. The failed attempt is not counted as review evidence.

### Dispatch storage baseline

`e267785` reuses call-description storage within each interpreter invocation under Fil-C. Recursive interpreter invocations retain separate storage; the storage is cleared after each call. The million-iteration `times` probe drops from 211184 KiB to 120556 KiB RSS. This does NOT resolve the Ractor memory problem: array-block probes remain near 480 MiB and a Ractor run still reached a sampled 4703 MiB. The execution-context lookup experiment did not help and was reverted.

Validation after dispatch reuse: all 2044 bootstrap tests pass; call/proc/super/keyword/iterator/fiber/thread selection passes 540 tests and 6894 assertions, with 3 skips; the complete spec run retains the same 2 failures and 10 errors. Logs: `build-reuse-calling.log`, `ta/pressure-{glibc,reuse-calling}-*.log`, `ta/reuse-calling-tests.log`.

Memory-pressure isolation:

- `probes/c/setjmp-oom.c` reproduces an OOM without Ruby: 40 pthreads repeatedly invoke a function containing `_setjmp`. After the first round and five explicit collections, FUGC reports 29 KiB live but RSS is 7364180 KiB; the next round is killed by the 8 GiB limit. GCC completes all four rounds around 1.5 MiB RSS. Logs: `ta/setjmp-oom.log`, `ta/setjmp-oom-native.log`.
- A smaller 40-thread run reaches about 3.4 GiB RSS; a single-thread control stays around 154 MiB. This establishes runtime allocation/collection pressure, not a retained-object leak or the exact allocator cause. Do not attribute it to issue #339 without further evidence.
- The current source checkout has a different setjmp implementation from the 0.686 binary. Upstream #335 records the post-release change and is closed. The latest published release is still 0.686. A short reproduction was attached to the existing issue before the source-built comparison above, explicitly untested against the unreleased change at the time: https://github.com/pizlonator/fil-c/issues/335#issuecomment-6357134997 . Local text: `upstream-bugs/setjmp-oom.md`. No new feature request or runtime redesign was undertaken.

Docker delivery:

- `example/Dockerfile` downloads pristine Ruby 4.0.7, checks its checksum, and applies `example/ruby-4.0.7-filc.patch`. It uses the checked local optfil archive in `example/dist/`; no previously built Ruby is copied into the image.
- Added netbase after a clean-build socket test exposed missing `/etc/services`. Set C.UTF-8 as the default locale. The smoke test now covers both, plus fibers, Fiddle, native-extension compilation, and an intentional bounds trap.
- With the earlier `e267785` image, Rack/WEBrick returned HTTP 200 and IRB evaluated `1 + 1`. Freshly compiled patched nio4r and unmodified Puma passed its concurrent/forced-GC probes. Current-image native-gem results are recorded separately above.
- The runtime audit checks 2059 ELF files, their interpreters, installed packages, libc archives, and loaded libraries. It identifies glibc 2.44 and no musl runtime/package. Two libc++ portability headers named musl.h remain and are explicitly reported, not hidden. Script: `port/audit-runtime.rb`; output: `ta/image-runtime-audit.log`.
- Build/application logs: `docker-build-4.0.7.log`, `app-build-4.0.7.log`, `smoke-4.0.7.log`, `ta/app-{http,server}-4.0.7.log`, `ta/irb-4.0.7.log`, `ta/puma-image-4.0.7.log`.

## Previous progress

- `3d6144f`: exposes measured live/allocated/collected object counts by allocation size and removes the Ruby-level GC.stat_heap placeholder. The counter probe passes on both stock and Fil-C Ruby. Unsupported page/generation fields are not invented.
- `08c3b64`: makes GC.stress perform collections on Ruby allocation paths, while retaining the supplied stress VALUE. The probe changed from zero collections to 23. Stress/lifetime/finalizer tests: 16 tests, 94 assertions, no failures/errors/skips. Collector-specific stress-mode bits are not fully implemented.
- `28025b9`: preserves ioctl/fcntl buffer capabilities through blocking calls rather than passing pointers through long. Fixes the full-spec safety trap; the pipe/FIONREAD probe now returns 3.
- `dc33bd0`: drains finalizers registered by shutdown finalizers before native cleanup. ObjectSpace specs: 112 examples, zero failures/errors. ObjectSpace/Tempfile tests: 82 tests, 1289 assertions, no failures/errors/skips.
- `3fe5106`: schedules finalizer interrupts only when cleanup is actually queued. Previously every stress collection posted an empty job, causing IO.select's reallocation/retry loop to spin indefinitely. The scheduler reproduction now finishes; all 19 scheduler tests pass (64 assertions). Pending cleanup is held in traced fields and consumed by the existing finalizer path.

Ruby 4.0.7 through the older `e267785` port is installed at `/opt/ruby-filc` inside the development container. OpenSSL, Psych, zlib and Fiddle load. The configured compiler is `/opt/fil/bin/filcc`. Installation log: `install-4.0.7.log`.

Native gems in `/work/native-gems`:

- nio4r 2.7.5 needed two integer/VALUE fixes, preserved in `port/native-gems/nio4r-2.7.5.patch`. The patched package builds; epoll, poll and select each pass 100 readiness events with forced collections and interest changes. No backend was disabled; Linux AIO and io_uring are untested.
- Puma 8.0.2 builds without source changes. A system probe serves 100 POST requests across five concurrent keep-alive clients, forcing GC in every request and checking the request-body digest. Synchronous shutdown passes.
- These are native-gem probes, not their full upstream suites or proof of full Rails compatibility. See `port/native-gems/README.md`, `ta/nio4r-runtime.log`, and `ta/puma-runtime.log`.

## Earlier progress

Commit `d5a89b7` removes the finalizer table's use of Fil-C zweak_map. A trailing per-object metadata structure now holds generic fields and the finalizer box. Ruby finalizers still run before native cleanup, including during shutdown. The Ruby GC adapter no longer uses zweak_map.

- `probes/ruby/finalizer-churn.rb` before the change: all 400000 finalizers ran, but RSS grew from 391 MiB after round 1 to 635 MiB after round 8. `ta/finalizer-churn-before.log`.
- After the change, a 16-round run completed all 800000 callbacks; RSS stayed in roughly 462-493 MiB after warmup. `ta/finalizer-churn-extended.log`.
- ObjectSpace/allocation/object/variable/marshal/string/clone/Tempfile suites: 922 tests, 14984 assertions, no failures/errors, 1 skip. `ta/finalizer-fields-tests.log`.
- Existing GC finalizer tests: 8 tests, 44 assertions, no failures/errors/skips. `ta/finalizer-gc-tests.log`.

Commit `05bc760` adds the actual FL_SHAREABLE flag to ObjectSpace metadata. The failing shareability test now passes; shareability and object-ID dump tests together: 2 tests, 8 assertions, no failures/errors/skips. Logs: `ta/shareable-before.log`, `ta/shareable-after.log`.

Ractor allocation-pressure investigation remains open. Stock completes the probe with about 12000 Ruby objects; Fil-C has a similar object count but generates much more C-heap traffic. Separate array/map/copy/share probes show high C allocation traffic even without Ractor copying. Three default-collector runs had sampled RSS peaks of 3834, 4301, and 780 MiB. A diagnostic FUGC_STW=1 run peaked at 907 MiB. This suggests allocation/collection pressure, but is not a root-cause finding or a shipped configuration change. Logs: `ta/ractor-{stock,glibc}-baseline-*.log`, `ta/ractor-phase-*.log`, `ta/ractor-array-profile.log`, `ta/ractor-stw-diagnostic.log`. Probe: `probes/ruby/ractor-port-phases.rb`.

The loader reproduction was rechecked with GCC and Fil-C. A short correction with a standalone reproduction was posted to existing issue #340: https://github.com/pizlonator/fil-c/issues/340#issuecomment-6354483332 . Different basenames and RTLD_LOCAL on the second load still reproduce the bug. No feature requests or new issues were filed. Local report: `upstream-bugs/issue2-followup.md`; output: `ta/dlsym-local-repro.log`.

## Earlier recovery and committed changes

For the earlier interruption, the user approved one OrbStack restart. That restart restored Docker, Postgres and the fabro-factory Linux machine; devcontainer-app-1, ruby-filc-build, and ruby-filc-glibc were started again. This approval does not cover the new interruption recorded above.

Commit `585246e`:

- `include/ruby/internal/memory.h`: RB_GC_GUARD performs a volatile VALUE load under Fil-C. Fixes premature T_DATA finalization during Ractor.select.
- `gc/filc/filc.c`: tracks every Ruby object; explicitly retains objects during GC.disable; bounds registry enumeration; implements Process.warmup string preparation; increments allocation count atomically. Fork hooks establish the VM barrier and hold/release the registry lock across fork.
- `io_buffer.c`: uses the existing allocate/copy fallback instead of unsupported mremap.
- `gc.c`: avoids temporarily pinning the entire registry around every NEWOBJ trace hook. The million-allocation reproduction now finishes. Explicit GC.disable is unchanged. The tracepoint suite still fails on missing GC events/statistics.
- `dln.c`: restores normal RTLD_GLOBAL/RTLD_LOCAL selection and adds RTLD_DEEPBIND under Fil-C when available. Fil-C can otherwise resolve an extension initializer to an already-loaded library's function. In particular, loading -test-/eval called libruby's Init_eval and changed interpreter state. This remains a loader workaround with different symbol lookup precedence, not an upstream runtime fix.
- `ruby.c`: uses Fil-C's zsetproctitle API, because rewriting its copied argv does not update the OS process title.

Commit `65ce529`:

- `vm_core.h`: rb_thread_t.ec is an atomic pointer under Fil-C. The timer thread reads it concurrently with fiber switches. The full test run caught a torn capability: timer_thread_check_timeslice tried to write through an address below the capability's lower bound. Atomic accesses cover all readers and writers of this field.

`example/Dockerfile` also installs tzdata and links /opt/fil/share/zoneinfo to /usr/share/zoneinfo. This is outside the Ruby source repository. Generated files are intentionally excluded from source commits and the export.

## Verification record

- Latest worktree build: success with the fix committed as `70c5604`, `build-metaclass-publication.log`; installed Ruby remains through `e267785`, `install-4.0.7.log`.
- Worktree bootstrap with registry trimming: PASS all 2044 tests, 127.99 seconds, `ta/btest-registry-trim.log`. This precedes the final reorder that preserves GC.disable state if trimming raises an allocation error; the subsequent full suites include that reorder.
- Latest complete worktree specs, through `e68cce3` and before the metaclass fix: 33763 examples, 156128 expectations, 1 failure, 10 errors, 0 tagged; 220.42 seconds. No Fil-C safety traps in this suite. `ta/test-spec-weak-callcache-final.log`. The later standalone concurrency probe did trap; full-suite coverage did not catch that race.
- Worktree lifetime and GC regressions: `ta/registry-trim-lifetimes.log`, `ta/registry-trim-gc.log`; counts and descriptor warnings above.
- Earlier `e267785` clean-image bootstrap, nobody/umask 022: PASS all 2044 tests, 141.39 seconds. `ta/clean-image-btest.log`.
- Earlier `e267785` clean-image test-spec, nobody/umask 022: 33763 examples, 154668 expectations, 2 failures, 10 errors, 0 tagged; 223.20 seconds. `ta/clean-image-spec.log`. No Fil-C safety traps. Ten errors are missing GC::Profiler; the two failures are mapped-buffer resize type preservation and unsupported signals.
- C-API specs before the ioctl and shutdown-finalizer fixes: all 1577 examples passed, `ta/capi-spec.log`. This is a separate run, not part of the full-spec count.
- Fiber/thread/Ractor suites after atomic EC change: 148 tests, 1732 assertions, 1 failure, 0 errors, 1 skip, `ta/atomic-ec-tests.log`. The remaining failure is the Ractor-port subprocess killed by SIGKILL. No safety trap in this run.
- Additional throwaway stress probe after atomic EC change: ten fresh processes, each running 100 threads x 1000 resumed fibers; all reach exactly 100000 increments. `ta/atomic-ec-stress.log`. This is not a Ruby suite result.
- Eval/trace/symbol/ERB/CGI after loader workaround: 673 tests, 4194 assertions, no failures/errors, 1 skip, `ta/deepbind-tests.log`.
- Process title tests: 2 tests, 12 assertions, no failures/errors/skips, `ta/proctitle-fixed.log`.
- Permission tests under an unprivileged user and umask 022: 439 tests, 2060 assertions, no failures/errors/skips, `ta/nonroot-permissions.log`. Stock Ruby reproduced the failures when run as root with the original umask: `ta/stock-permissions.log`.
- Ractor-port and refinement-repeat tests in isolation before atomic EC change: 2 tests, 10 assertions, no failures/errors/skips, `ta/refine-ractor-targeted.log`. The refinement test took about 9.7 seconds against its normal 10-second timeout.
- Fiddle probes: strlen invocation, pointer/address round trip, and Ruby object dlwrap/dlunwrap all pass. `ta/fiddle-{call,pointer,object}.log`. The bundled Fiddle distribution does not include its test suite; these are only smoke probes.

Earlier targeted results still relevant: timezone 156 tests / 1243 assertions; encoding and transcoding 112 / 4958; allocation/ObjectSpace/string-memory/IO::Buffer 196 / 4049 with 2 skips; Ractor bootstrap 154 pass. Logs: `ta/timezone-fixed.log`, `ta/encoding-guard.log`, `ta/objectspace-fixed.log`, `ta/btest-ractor-fork.log`.

## Completed full test-all runs

Latest complete worktree run includes the weak-cache fix but predates its final debug-only additions and the metaclass fix: 33345 tests, 7244616 assertions, 33 failures, 17 errors, 208 skips. Log: `ta/test-all-weak-callcache-class.log`. Relative to `19f520d`, Rational GCD memory growth failed and class-extension memory growth passed; the total remained unchanged. The complete `74beca5` clean-image recovery run has 33334 tests, 36 failures and 17 errors, as recorded above. These are historical results; the complete current `70c5604` clean-image result is recorded above.

Earlier worktree, changes committed as `5f70d87`, WITH normally excluded memory-leak tests:

- Run as nobody, umask 022, 8 GiB limit; override `TEST_EXCLUDES=--excludes-dir=/work/ruby-4.0.7-glibc/test/.excludes` and use `TESTOPTS="-j2 --no-retry --timeout-scale=3"`.
- 33342 tests, 7245609 assertions, 32 failures, 17 errors, 208 skips; 805.45 seconds. Actual make exit 2; no Fil-C safety traps. `ta/test-all-with-leaks-registry-trim.{log,status}`; details `ta/failures-with-leaks-registry-trim.txt`.
- The 41 non-leak failures/errors are GC 22, RubyOptions 9, Process 4, ObjSpace 3, TracepointObj 2, BugReporter 1. The eight leak failures are ISeq keyword loading, TracePoint, class extensions, autoload, Ripper compile-error callbacks, empty WeakMap creation, iclass, and complemented method entries. Ractor and named Struct were not reported as failures this run; neither is established fixed across runs.
- Descriptor warnings also occur in the full logs, including the scheduler/compile stress case. They are not counted as assertion failures.
- Before registry trimming, with scavenging and sized realloc: 33350 tests, 7247376 assertions, 36 failures, 17 errors, 208 skips; 768.63 seconds, no safety traps. `ta/test-all-with-leaks-scavenge.log`. Bootstrap passed 2044; specs had 33763 examples, 2 failures, 10 errors.

Previously built clean image, with the patch through `e267785`, netbase and UTF-8 locale:

- Run as nobody, umask 022, 8 GiB limit; `make test-all TESTOPTS="-j2 --no-retry --timeout-scale=3"`.
- 33285 tests, 7243200 assertions, 25 failures, 17 errors, 247 skips; 636.77 seconds.
- No Fil-C safety traps. `ta/clean-image-test-all.log`; extracted details in `ta/clean-image-failures.txt`.
- Failure/error groups: TestGc 22, TestRubyOptions 9, TestProcess 4, TestObjSpace 3, TestTracepointObj 2, TestBugReporter 1, TestStruct::TopStruct 1. The Ractor case passed in this run, but remains flaky. Do not treat an unchanged failure total as an unchanged failure set.
- The named-Struct RSS assertion failed at 276365312 -> 557326336 bytes (2.0166x, limit 2x). A targeted worktree rerun failed both variants at 2.13x/2.05x. No assertion was changed. Logs: `ta/struct-retention-test.log`.
- `probes/ruby/struct-retention.rb` creates and discards 10000 named Struct classes in each of ten rounds, with five explicit collections per round. The final image's class count stabilizes at 408 (two named Struct::A classes visible), and RSS settles near 359 MiB after the initial peak. The worktree miniruby similarly stabilizes at 306 classes / two named classes / roughly 334 MiB. Native ARM64 stock miniruby stays at 303 classes, zero named classes, and roughly 10-12 MiB. This did not show a growing class population; it does not resolve the suite's RSS failure or establish general leak freedom. Logs: `ta/struct-retention-{image,worktree,stock-arm64}.log`. The separate `struct-retention-stock.log` used an amd64 Docker image under emulation and is not the architecture-matched control.
- The earlier clean image without netbase ran 32346 tests, with 24 failures and 18 errors. Its additional socket error was resolving the service name ssh, and is now fixed. All 758 test files were dispatched in both runs; the final packaging changes enabled 939 additional cases. Earlier log: `ta/clean-image-test-all-before-netbase.log`.

Worktree at `3fe5106`, before dispatch reuse:

- Run as nobody, umask 022; `make test-all TESTOPTS="-j2 --no-retry --timeout-scale=3"`.
- 33303 tests, 7244632 assertions, 25 failures, 17 errors, 209 skips; 616.49 seconds.
- No Fil-C safety traps. `test-all-glibc.log`; extracted details in `ta/current-failures.txt`.
- Failure/error groups: TestGc 22, TestRubyOptions 9, TestProcess 4, TestObjSpace 3, TestTracepointObj 2, TestBugReporter 1, TestRactor 1.
- The preceding run timed out at 1200 seconds in the scheduler stress test. It has no aggregate result and is preserved as `ta/test-all-scheduler-timeout.log`. Commit `3fe5106` fixes that stall.

After the allocation-hook fix, before loader/process-title fixes:

- `make test-all TESTOPTS="-j3 --no-retry"`
- 33322 tests, 7244278 assertions, 39 failures, 24 errors, 220 skips.
- About 450 seconds; no Fil-C safety traps.
- Saved as `ta/test-all-before-deepbind.log`.

After loader/process-title fixes, BEFORE atomic EC change:

- Run as user nobody, umask 022; `make test-all TESTOPTS="-j1 --no-retry --timeout-scale=3"`.
- 33250 tests, 7244470 assertions, 27 failures, 19 errors, 209 skips.
- 1380.39 seconds; one Fil-C safety trap, subsequently addressed by atomic EC change.
- Archived as `ta/test-all-before-real-stress.log`; extracted details in `ta/failures-before-real-stress.txt`.
- Failure/error groups: TestGc 24, TestRubyOptions 9, TestObjSpace 4, TestProcess 4, TestTracepointObj 2, TestRactor 1, TestBugReporter 1, TestFiber 1.

The historical clean-image and pre-memory-fix worktree runs above use the default memory_leak name exclusion. The newest worktree full runs explicitly remove that name exclusion, and all 67 matching tests have also been run separately. The standard excludes directory remains in use. --no-retry does not skip failures. Longer timeouts do not weaken assertions.

## Remaining issues

1. GC API compatibility: remaining statistics/stat_heap fields, config, latest_gc_info, profiler, collector-specific stress modes, internal trace events, generation/compaction behavior, and ObjectSpace dump fields. Do not manufacture default-GC page/generation statistics. Some tests assume the default collector, but public API omissions are genuine compatibility gaps.
2. SIGSEGV/crash-report integration: Fil-C explicitly disallows handlers for SIGSEGV/SIGBUS/SIGILL/SIGFPE/SIGTRAP in libpas/src/libpas/filc_runtime.c:is_unsafe_signal_for_handlers. Ruby's handlers remain disabled. Making the tests pass by intercepting Process.kill would not solve real crash reporting.
3. Ractor-port memory pressure remains. The test sometimes passes and sometimes gets SIGKILL at the 8 GiB limit. A standalone C `_setjmp` workload now reproduces comparable pressure without Ruby; see the latest-progress section. A coherent post-release compiler/runtime now completes the controlled C reproduction and three Ruby Ractor probes, but sampled memory remains high. Those Ruby probes predate the newest adapter fixes. The setjmp ABI changed, so replacing only one runtime library is not a valid upgrade. Earlier Ruby probe: `probes/ruby/ractor-port-pressure.rb`, `ta/ractor-memory.log`. The precise runtime allocator/collector cause remains unresolved.
4. TestProcess#test_daemon_no_threads sees 4 native threads, versus the default collector's expected 1..2; Fil-C has runtime threads.
5. IO::Buffer shared shrinking/regrowth and mapped-type preservation are fixed in the worktree using supported runtime APIs, not just flag changes. The current clean runtime image includes these fixes. Private file-backed relocation remains unsupported by Fil-C; copying loses file association, as demonstrated above. Full private-mapping parity remains unresolved.
6. Memory behavior remains incomplete: the latest serial leak selection has seven failures and the latest complete parallel worktree run has nine. The named-Struct RSS test failed in the earlier clean image and targeted rerun, despite bounded class counts; it is not a reported failure in the newest worktree full run. Allocation/collection footprint and deferred native cleanup still need investigation. No memory assertion has been skipped or weakened.
7. Remaining broader gaps: callcc, moving compaction, M:N migration, weak VM tables, native-gem coverage beyond the patched nio4r/Puma probes, amd64 verification, and full Rails application testing. The Ruby-level finalizer zweak_map use has been removed and the churn probe plateaus.

## Reproductions and next actions

- `probes/ruby/gc-hook.rb`: million-allocation trace hook reproduction, now completes.
- `probes/c/binding/{a.c,b.c,main.c}`: two different library basenames exporting Init_eval. Loading the first globally causes the second's dlsym to return the first function, whether the second is local or global. RTLD_DEEPBIND fixes this reproduction. This broadens the earlier same-basename diagnosis; the verified correction is now posted on issue #340.
- `probes/ruby/ractor-port-pressure.rb`: Ractor workload with RSS sampling; `probes/ruby/refine.rb`: refinement churn with explicit collections and RSS sampling.
- Latest complete worktree failures are in `ta/test-all-weak-callcache-class.log` and `ta/test-all-weak-callcache-class-failure-names.txt`; earlier details remain in `ta/failures-review-fixes.txt`, `ta/failures-with-leaks-registry-trim.txt` and `ta/current-failures.txt`. Prioritize actual runtime safety, memory behavior, and public API gaps rather than suppressing assertions.
- `probes/ruby/scheduler-stress.rb`: minimal scheduler/compile/stress reproduction; now completes. Stack/cycle diagnostics: `ta/scheduler-stack-dump.log`, `ta/scheduler-stress-cycles.log`; passing suite: `ta/scheduler-fixed-tests.log`.
- `probes/ruby/gc-counts.rb`, `probes/ruby/gc-stress.rb`, `probes/ruby/ioctl.rb`: counter/stress/buffer capability probes. `probes/ruby/nio4r.rb`, `probes/ruby/puma.rb`: native-gem system probes.
- Continue Ruby-side weak-table/retention and mapped-buffer work; investigate Ractor allocation pressure. Some missing profiler/events/signal behavior needs runtime facilities and must respect the upstream boundary above.
- The reviewed metaclass fix, exported patches, clean images and application checks now agree at `70c5604`. Continue the actual remaining failures: weak CME/refinement/overloaded tables, memory growth and OOM pressure, delayed native cleanup, descriptor warnings and GC APIs. Remaining validation includes skip auditing, further native gems, amd64, and a full Rails application.
- Docker is healthy again. The previous recovery approval was incident-specific and no restart was needed. Preserve outage logs and require fresh approval for another shared-infrastructure disruption.
- Extend the source-built compiler/runtime validation to current Ruby sources and freshly rebuilt native dependencies, not an ABI-incompatible library swap. Respect the upstream boundary; no feature/design request is authorized.
- Investigate why a full collection followed by native finalization requires a later collection to reclaim storage. Preserve finalizer context/reentrancy and scheduler behavior; do not hide this by changing test collection counts.
- Do not label the current port fully compatible.

## Source patch

Export: `python3 -I /tmp/ruby-filc/port/export-current.py`.

Current export: `ruby-4.0.7-filc.patch`, 142 files, +2672/-1094, 369111 bytes, 9945 lines. Includes source commits through `70c5604`. Generated files are excluded; `git apply --check` passes against pristine Ruby 4.0.7. The example's patch is identical and the current images were rebuilt from it. The prior example patch is preserved as `port/example-through-e267785.patch`. The normal-CME candidate in vm_callinfo.h and vm_insnhelper.c is uncommitted and excluded from the current exported patches/images. Other tracked modifications are generated gc.rbinc, miniprelude.c, revision.h and vm.inc; build artifacts are also untracked.
