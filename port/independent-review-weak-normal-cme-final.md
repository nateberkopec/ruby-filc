# Independent review: weak normal-call-cache CME final candidate

**Baseline:** `70c560472a3f5fe0e669c5bff70e9ae368968480`  
**Authoritative patch:** `/tmp/ruby-filc/port/weak-normal-cme-final.patch`  
**Verified SHA256:** `3a541bc07270b837f293c53c45d38396aa6f60c099047fdd8868b433a1cb7098`  
**Scope:** `vm_args.c`, `vm_callinfo.h`, `vm_eval.c`, `vm_insnhelper.c`, `vm_insnhelper.h` (`+143/-98`)

The live source diff for those five files is byte-for-byte identical to the frozen patch. Generated build-file changes and artifacts were excluded.

## Findings

No issues found.

## Functional-correctness review

### Weak call-cache representation

- `vm_callinfo.h:351-398` weakens `cme_` only for Fil-C `cc_type_normal` heap caches. Super and refinement entries remain direct.
- The source CME is retained through weak-cell and call-cache allocation by `RB_GC_GUARD(cme_value)` at `vm_callinfo.h:394-396`.
- `vm_cc_cme` resolves weak CMEs only for markable, non-super, non-refinement caches (`vm_callinfo.h:472-489`); unmarkable stack caches retain direct pointers.
- Both heap-to-stack transitions resolve the representation:
  - attr-set temporary cache at `vm_insnhelper.c:4968-4981`;
  - protected-call cache at `vm_insnhelper.c:5101-5106`.
- The Fil-C invalidation check retains the resolved class while consulting the weak CME (`vm_callinfo.h:531-538`), preserving the class-table ownership invariant during the check.

### TracePoint reentrancy

The prior P1 is corrected:

- `VM_CALL_METHOD_ATTR` now receives an already resolved CME, uses it for both event metadata and the accessor operation, and retains it through the `:c_return` hook with `RB_GC_GUARD` (`vm_insnhelper.c:4869-4884`).
- Initial attr and Struct dispatch captures the CME before the callback and passes that same entry through the direct helpers (`vm_insnhelper.c:4890-4921`, `vm_insnhelper.c:4933-4997`).
- `vm_call0_body` refreshes its CME at the retry label and uses the captured entry for attr and Struct event paths (`vm_eval.c:201-206`, `vm_eval.c:233-244`, `vm_eval.c:295-306`).
- The current accessor operation and `:c_return` metadata therefore continue to describe the method selected before a hook removes or replaces it, matching stock behavior, without rereading an invalidated weak cache after the hook.
- Fast-path handler signatures remain unchanged. The new direct helpers isolate the pinned-CME path from ordinary fast handlers.

The supplied status files show all 16 attr/Struct reader/writer, direct/`public_send`, removal/replacement combinations passing on stock, normal Fil-C, and checked Fil-C.

### Warning.warn and argument setup

- Ruby-method dispatch captures the CME before argument handling (`vm_insnhelper.c:3455-3488`).
- That entry is passed through `vm_callee_setup_arg` and used consistently for the unused-block warning, arity errors, keyword setup, and complex parameter setup (`vm_insnhelper.c:3221-3384`; `vm_args.c:588-593`, `vm_args.c:869-965`).
- Normal and tail frame creation receives the same resolved entry rather than resolving the cache again after `Warning.warn` can run arbitrary Ruby (`vm_insnhelper.c:3491-3562`).
- Cacheability decisions use the supplied CME and first require a still-valid cache class (`vm_insnhelper.h:263-275`), avoiding the former post-callback weak-CME lookup on the tested leaf invalidation path.
- Bmethod complex argument setup likewise receives the already resolved entry (`vm_insnhelper.c:4166-4211`).

The supplied warning matrix passes on stock, normal Fil-C, and checked Fil-C for simple, optional, explicit/default keyword, complex, tailcall, and arity-error paths. The tailcall probe confirms that a `TAILCALL` instruction was actually generated.

### Alias retries and tailcalls

- `vm_call0_body` assigns `cme = vm_cc_cme(cc)` at the `retry` label (`vm_eval.c:203-204`). When an unmarkable alias cache is rewritten to its original entry and retries (`vm_eval.c:263-275`), the next iteration therefore switches on the replacement entry rather than retaining the alias CME from the prior iteration.
- Markable alias calls continue through a new direct on-stack cache, preserving the existing behavior.
- Tailcalls now receive the resolved CME explicitly from general setup through `vm_call_iseq_setup_2` and into frame construction (`vm_insnhelper.c:3491-3502`, `vm_insnhelper.c:3522-3562`).
- Existing zero-start and optional-argument tail fastpaths resolve immediately before entering the tailcall helper (`vm_insnhelper.c:2728-2734`, `vm_insnhelper.c:3043-3065`); there is no intervening Ruby callback in those fastpaths.

I found no changed argument-count, keyword, stack-pointer, frame-layout, event-order, or alias-selection semantics.

## Validation evidence and limitations

Reviewed evidence includes:

- normal and VM-check bootstrap: 2044 passing tests each;
- all focused TracePoint and Warning.warn status files: exit 0;
- lifetime, isolation, protected-dispatch, and four-Ractor invalidation comparisons: passing across stock, normal, and checked builds;
- C-API suite: 1577 passing examples;
- full revised test-all: 33362 tests, 33 failures, 17 errors, with no added failure identities versus the previous candidate;
- full specs retaining only the known signal and `GC::Profiler` failures.

No build or runtime command was run during this review, as required.

Remaining validation gaps are not demonstrated defects in this patch:

- clean-image validation has not run;
- full suites remain red for known port limitations;
- the completed test-all run incurred an OOM kill, a Ractor-port SIGKILL, and descriptor warnings;
- the focused Warning.warn matrix does not separately combine the callback with an alias chain or inherited-method tree invalidation, although the source paths are correctly threaded and broader alias/invalidation coverage passed.

**Merge verdict: OK with notes**