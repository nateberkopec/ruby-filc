# VM-stack retirement candidate

Recovery update: this report records the pre-recovery candidate and its review. The exact reviewed patch was recovered and is now committed in the local source worktree, with the original patch hash unchanged. Full-suite acceptance is still outstanding. New recovery checks and the disposition of old log paths are in [RECOVERY.md](../RECOVERY.md).

The committed/exported port and released-toolchain Docker images remain at `78e4bb7`. The current uncommitted candidate changes `vm.c`, `vm_core.h`, and `vm_insnhelper.c`. It has been built into the newer-toolchain normal runtime and a separate checked miniruby, but has not been accepted, committed, exported, or published.

## Reproduction and root paths

`tvm-stack-lifetime.rb` allocates 100 strings through recursive Ruby calls, returns those calls, suspends the still-live Fiber, and performs one full/immediate collection. It requires exactly zero live WeakMap keys. Stock Ruby 4.0.7 Linux and host Ruby 4.0.5 pass; baseline Fil-C retains 99.

The initial probe used WeakMap#size, which includes unpruned dead entries on stock. That measurement was invalid; original direct/Fiber programs and logs are retained in `ta/`. The corrected probe enumerates keys without changing the collection count or exact lifetime requirement.

A freshly compiled diagnostic extension reports the Fiber VM-stack allocation and calls Fil-C's native heap dumper. Before the fix, all 99 surviving keys have root paths through that allocation. After the revised full-runtime build, none of the 100 watched objects have a root path. Evidence:

- `ta/vm-stack-lifetime-fiber-{stock,filc}-live-keys.*`
- `ta/vm-stack-heap-build.*`, `ta/vm-stack-before-{heap,targets,paths}.txt`
- `ta/vm-stack-after-build.*`, `ta/vm-stack-after-{heap,targets,paths}.txt`
- `ctest/vm-stack-heap/filc_vm_stack_heap.c`, `tvm-stack-heap.rb`

The first diagnostic-extension build used a hidden execution-context getter and failed to load with an undefined symbol. The corrected helper accesses the current Thread's data using matching internal headers. Original failure: `ta/vm-stack-heap-build.*.before-ec-access`.

## Candidate and corrections

Retirement clears the retired frame header and the value-stack range from the caller's SP through the maximum of current SP and the Ruby frame's base plus stack_max. Dummy ISeq frames do not use their ISeq's unallocated layout. A tailcall preserves arguments until they have been copied and the replacement frame created.

The first frozen patch, `port/vm-stack-clear-candidate.patch`, has SHA256 `38512a1fbdd51e378da9791f2e99ec1d922f7143e4b4ef54238027f8bd888c33`. Its independent review is BLOCK: `port/independent-review-vm-stack-clear.md`, run `09936caa-98c2-49ab-b6b9-0ee796498999`, mission `160df604-c074-4017-8731-75efedc94ced`. An initial launch was rejected for an unsupported tools option before any child started; the corrected same-model launch completed.

Two issues were reproduced and corrected:

1. The reviewer identified a tailcall whose replacement frame overflows. The original cleanup lay after vm_push_frame, so the exception bypassed it. `tvm-stack-tail-overflow.rb` verifies actual TAILCALL compilation and a callee stack_max of 20001, rescues SystemStackError, and checks zero live keys while the Fiber remains alive. Stock passes; the initial candidate retains one key. The revision uses the same extracted overflow predicate as the ordinary stack check, clears the discarded outgoing frame and copied argument range before raising, and passes on normal and checked builds.
2. VM_CHECK_MODE=1 plus VM_DEBUG_BP_CHECK=1 exposed a startup trap: a C frame's EP was null. An unchanged checked control starts successfully. Native traces identify REWIND_CFP in the FrozenCore alias/undef helpers: it temporarily hides a C frame, nested calls reuse and now clear that slot, and the macro then reactivates the cleared frame. The Fil-C macro now saves/restores the complete hidden frame before republishing it, retaining the existing temporary SP handling. Both assertions remain enabled. `tvm-stack-rewind.rb` exercises alias/undef callbacks with collection; it and startup pass after correction. Original failures and diagnostic traces: `ta/vm-stack-retirement-checked-*`, `ta/vm-stack-debug-*`. The diagnostic logging is only in `ta/vm_insnhelper-frame-debug.c`, not the candidate source.

Revised frozen patch: `port/vm-stack-clear-revised.patch`, three files, +83/-4, SHA256 `9147af50928511bfe5b0e6b171228324c814b59ca33c6ad9bcaf18eec37023f6`. Same-model follow-up run `97ca15a8-36b1-4ada-af50-fa4c46057690` verified that exact diff and returned OK with notes, with no concrete source findings. It confirmed the original overflow bypass is resolved and audited rewind restoration, exception exits, closure/C-frame lifetimes, forwarding geometry, and non-Fil-C behavior. Report: `port/independent-review-vm-stack-clear-revised.md`. The parent read the report and closed the bounded review mission as completed; full runtime acceptance remains outstanding.

## Validation

The compiler/runtime are the coherent source build at `9d1ed206e0ccfc1ec114471386befeba643a5f86`. Normal source/install paths remain in `ta/ruby-cme-current-toolchain-path.txt`. The checked build path is in `ta/vm-stack-checked-build-path.txt`; it uses both VM_CHECK_MODE=1 and VM_DEBUG_BP_CHECK=1.

- The original exact-zero lifetime probe passes on normal and checked miniruby.
- `tvm-stack-retirement.rb` covers normal return, raise, throw, ten intentionally held closures, nested C frames, receiver lifetime, argument forwarding, successful tailcalls with argument preservation, and reentrant return TracePoints. All nine modes pass on both builds. The baseline Fil-C runtime fails all nine lifetime checks.
- The first C-frame stock control retained one conservative native residue. One final C call over an untracked symbol array removes that ambiguity; the exact-zero assertion and single collection are unchanged. The corrected stock control passes, baseline Fil-C retains 99, and the candidate passes. Original program/logs are retained with `before-cframe-control` names.
- The tailcall-overflow and rewind probes pass on normal and checked builds. `ta/vm-stack-revised-{normal,checked}-{lifetime,rewind,tail-overflow}.*`.
- Normal bootstrap: 2044 passed, 137.78 seconds. Checked bootstrap: 2044 passed, 166.85 seconds. Each build also passes all 50 existing standalone cache, reentrancy, concurrency, GC-state, retention, and buffer regressions. `ta/vm-stack-revised-{normal,checked}-{btest,regressions}.*` and per-probe statuses.
- The host command running those validations was interrupted, but the remote driver finished. The four individual suite status files are zero and their logs contain complete results; the outer aggregate status is missing and is not treated as a successful receipt. No rerun was used to replace this evidence.
- The full normal runtime and extensions rebuilt and installed, status zero: `ta/vm-stack-full-build.*`. A static normal baseline miniruby was first built from HEAD and saved beside the source as `miniruby-vm-stack-baseline`; `miniruby-vm-stack-revised` preserves the pre-install candidate binary. This permits a same-toolchain resource comparison without accidentally loading a new shared libruby into an old executable.
- Full test-all/spec/C-API validation was launched with the unchanged 8 GiB/no-swap/CPUs 0-3 limits, nobody/umask 022, leak names enabled, -j2, no retries. Docker stopped responding while test-all was only at 36/758 dispatched files. The host command timed out after 3430 seconds; no suite status or aggregate exists. `ta/vm-stack-full-validation.log`, `ta/vm-stack-full-test-all.log`. This is interrupted validation, not a suite result or proof of a Ruby deadlock.

## Forwarding and tailcall cross-product control

The follow-up reviewer noted that the existing runtime probes exercise forwarding and tailcalls separately. `tvm-stack-forward-tail.rb` now prepares a combined probe with both outgoing-only and bidirectional tailcalls. It verifies actual sendforward instructions and TAILCALL flags, checks argument/keyword/block preservation, and retains the exact-zero/single-GC lifetime requirement.

The first shape incorrectly required sendforward itself to have a TAILCALL flag. Stock Ruby 4.0.5 disassembly and this Ruby 4.0.7 source's compile.c:4005-4007 show that this optimizer marks send/invokesuper, not sendforward. That invalid control and its disassembly/failure are preserved as `ta/vm-stack-forward-tail-before-sendforward-control.rb`, `ta/vm-stack-forward-tail-disasm-stock-darwin.log`, and the `.before-sendforward-control` logs/statuses.

The corrected shape forwards to a capture method, then makes an explicit tailcall from the forwardable frame. In outgoing mode this passes on host stock Ruby 4.0.5, including zero remaining keys. In both mode, which also tailcalls into the forwardable method, the same stock runtime raises ArgumentError: given 99, expected 3, required keyword label. Both statuses/logs are preserved in `ta/vm-stack-forward-tail-{outgoing,both}-stock-darwin.*`; the failing case has not been removed or relaxed. This is not yet attributable to Fil-C: stock Linux 4.0.7, baseline Fil-C and candidate normal/checked comparisons await Docker recovery. No production source changes were made in response to this control result.

## Remaining work

Recover/inspect the pending remote validation before rerunning anything. Complete full Ruby/spec/C-API validation, both forwarding/tailcall controls on Linux, fresh installed-runtime/native-extension checks, and controlled resource comparisons. Update packaging only after acceptance.

This fixes a demonstrated source of retention in retired VM frames. It does not establish that the Ractor OOM is resolved. Discarded operand slots inside still-active frames, native allocation/scavenging pressure, and the other documented GC, signal, mapping, dependency, application, and architecture gaps remain separate requirements for the overall port.
