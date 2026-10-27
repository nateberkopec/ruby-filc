# Checked arithmetic and CPU-feature initialization

These are isolated Ruby 4.0.9 / Fil-C 0.687 amd64 candidates, not a claim that the 5% Puma goal is met. The consolidated exports and default Docker configuration are unchanged. Both patches apply directly to the consolidated baseline; the measured combined build also uses the previously documented `-g0` configuration.

## CPU work, not mainly waiting

`puma-order-hotpaths.rb` now records main-thread CPU time as well as process CPU and wall time. In a 20,000-iteration non-HTTP run, baseline Fil-C takes 11.873 seconds elapsed, 11.819 seconds on the main thread, and 17.164 seconds of process CPU. Stock takes 1.422 seconds elapsed and approximately the same main-thread CPU time. The Fil-C main thread is running for over 99% of this diagnostic's elapsed time; removing collector waiting alone cannot explain away the gap.

Separating threads in the earlier native profile assigns 69.9% of user-CPU samples to the main thread. Collector/runtime workers account for most of the rest. This is not an HTTP latency decomposition. A generator-only main-thread profile, with call stacks and zero lost samples, identifies checked-size temporaries, string-search state, `rb_ensure`, pointer-metadata allocation and copying among the costs.

An experimental boolean fast path for the allocation-time `GC.stress` check removes an atomic pointer load, but alternating diagnostics do not establish a meaningful speedup. It is not carried forward. The original adapter source is restored; its experimental diff/library remain only in ignored local artifacts.

## Checked-size arithmetic without aggregate temporaries

`checked-size-arithmetic-ruby-4.0.9.patch` changes only the Fil-C branches of `rbimpl_size_mul_or_raise` and `rbimpl_size_add_or_raise`. The usual aggregate-return helper can materialize a managed temporary, including for a byte-sized `MEMCPY`. The candidate keeps the calculation scalar:

- Multiplication rejects a nonzero second operand when the first exceeds `SIZE_MAX / second`.
- Addition rejects unsigned wraparound.
- Both retain the original overflow-error functions and messages.
- Non-Fil-C implementations, allocation-size policy, and memory-access safety checks remain unchanged.

The native probe compares actual helpers against Ruby arbitrary-precision arithmetic. It exercises boundary products/sums, zero, maximum-size operands, 10,000 deterministic random pairs, and constant byte/VALUE element sizes. Stock, baseline Fil-C, a candidate-header Fil-C extension, and GCC with the patch overlaid on pristine stock headers each pass **21,404 checks**. The combined runtime passes the same probe. The changed header also compiles as C++17 with Fil-C. Disassembly of the constant-byte helper shrinks from 263 to 160 bytes and no longer contains the native temporary-allocation/memset calls.

A controlled generator-extension comparison rebuilds identical source with identical `-ggdb3` flags, changing only the header. Two baseline runs deliver 15,071 and 15,098 generation iterations/s; two candidate runs deliver 15,942 and 15,806. Allocation counts at the Ruby level are unchanged. This roughly 5% generator-only improvement is diagnostic, not HTTP acceptance evidence.

## Initialize the existing CPU-feature detector

A standalone x86-64 Fil-C program reports SSE2 and AVX unavailable before `__builtin_cpu_init()`, then available afterward. GCC reports them available both before and after. A separately built Ruby extension confirms the shared-table behavior: stock reports SSE2 available on entry, whereas baseline Fil-C reports it unavailable until explicitly initialized.

JSON already compiles its SSE2 implementation, but chooses its implementation through `__builtin_cpu_supports("sse2")`. The uninitialized table therefore selects its scalar fallback. The previously suspected absence of SIMD code was not the issue.

`cpu-feature-init-ruby-4.0.9.patch` initializes the existing detector in `ruby_setup`, before Ruby initialization or extension loading, only for Fil-C on x86-64. It does not assert that any optional CPU feature exists, force a SIMD implementation, alter detection results, or disable checks. Other architectures and GCC builds are unchanged. Placing this in library setup also covers embedding instead of only the executable's `main`.

The startup probe checks SSE2 availability **before** invoking any explicit initialization. It fails on baseline Fil-C and passes on stock and the combined candidate; repeated initialization remains stable. In separate alternating diagnostics using the original interpreter and standard extensions, explicit initialization improves parsing from 3,332-3,378 to 3,644-3,669 iterations/s. Generation is essentially unchanged for the short strings in this workload. The complete non-HTTP operation improves from 1,663-1,754 to 1,837-1,839 iterations/s. None of these numbers substitutes for HTTP measurements.

## Combined validation

The combined `-g0` build passes:

- All **2,044 bootstrap tests**.
- Array/Hash/String/Exception/JSON selection: **1,515 tests, 35,670 assertions, zero failures/errors, 24 skips**.
- All **21,404** arithmetic checks and the CPU-feature startup/idempotence probe.
- nio4r epoll/poll/select and the existing 100-request/five-client Puma probe.

The first header-only build/test command chain exited zero, but its detached Docker log capture was incomplete. It is not used for reported suite counts. The final combined run captures the complete build/test log inside the container before it exits. Neither an independent checked build nor a full Ruby-suite result is claimed for these candidates. The intrusive native-gem GC probes are separate from acceptance rounds.

## Matched HTTP measurements

Six completed runs alternate stock, prior `-g0` control, combined candidate, combined candidate, prior `-g0` control, stock. Each uses the unchanged 70,000-response workload, 4 GiB/no swap, server CPUs 0-3, client CPUs 4-7, and no concurrent build or explicit collection/scavenging during measured rounds.

The control selects the existing `-g0` Ruby library with the original installed standard extensions. The combined candidate selects the patched `-g0` Ruby library **and rebuilt `-g0` standard extensions** so their inline size helpers use the candidate header. Existing Puma/nio4r native gems and toolchain libraries are unchanged. Thus this comparison measures the combined configuration, not the source patches independently. Whole-process RSS includes every loaded component. The `-g0` native file/line diagnostic trade-off still applies.

| Run | Median RSS, KiB | Peak RSS, KiB | Requests/s | p50, ms | p95, ms | p99, ms |
|---|---:|---:|---:|---:|---:|---:|
| 1 stock | 36,084 | 39,740 | 3,479.5 | 1.192 | 2.402 | 3.672 |
| 2 `-g0` control | 177,160 | 184,664 | 792.4 | 5.796 | 11.167 | 14.679 |
| 3 combined | 176,348 | 182,112 | 814.3 | 5.648 | 10.950 | 14.342 |
| 4 combined | 176,224 | 184,980 | 814.5 | 5.630 | 11.078 | 14.394 |
| 5 `-g0` control | 178,076 | 184,068 | 786.3 | 5.839 | 11.355 | 14.745 |
| 6 stock | 36,340 | 38,880 | 3,470.0 | 1.194 | 2.399 | 3.787 |

The mean of the two candidate throughput results is about **3.2% higher** than the two `-g0` controls, with lower latency in both candidate runs. Median RSS is only about 0.7% lower; one candidate peak exceeds both controls, so this is not a reproducible peak-memory improvement. The recorded GC count is 1,410 for each candidate versus 1,434 for each control.

Every stock-relative numeric gate still fails. The first candidate uses **4.887x stock median RSS**, delivers **23.4% of stock throughput**, and has **4.740x stock p50 latency**. Both stock runs fail the warmed-growth screen (+15.5% and +13.2%); the candidate runs pass (-4.8% and +3.6%). Client CPU utilization stays below 28%. All responses and shutdowns succeed. The driver exits zero; the comparators correctly fail. These results do not establish sustained reliability, full compatibility or general object/resource reclamation. Neither patch is promoted.

## Reproduction and identities

The build-only helper accepts optional patch paths after its four required arguments:

```sh
bash port/build-nodebug-candidate.sh tmp/ruby-4.0.9.tar.xz tmp/sizes-cpu-build \
  tmp/install-stock/bin/ruby tmp/install-filc \
  port/checked-size-arithmetic-ruby-4.0.9.patch \
  port/cpu-feature-init-ruby-4.0.9.patch
(cd tmp/sizes-cpu-build && make test-all TESTS='json')
```

Use a new build directory and matching `/opt/fil` toolchain/dependencies. The helper does not install into or modify the control prefix. For this experiment, copy the built library with its soname links to an isolated directory and the built `.ext/x86_64-linux` tree to another isolated directory. Set `LD_LIBRARY_PATH` and `RUBYLIB` only for the candidate. Verify loaded paths and hashes in the receipt and mapping snapshots; do not propagate these overrides to the stock interpreter.

Build `probes/c/checked-size/` and `probes/c/cpu-features/` with each matching Ruby using `extconf.rb` and `make`, then run their corresponding probes with `-I`. To test just the changed header, the extension Makefile accepts `hdrdir=/absolute/path/to/candidate/include`. The CPU-feature probe is specifically x86-64; SSE2 is mandatory there.

Combined library SHA-256: `03aef2370d01e656013a206b8e701c5a630581d552325fe10551e0f6a1752021`. Header-only library SHA-256: `3e4d728e3a13ace79b356b57eaac121f87d6a298821759e1f984068b6a5d1e3a`. The consolidated patch remains `eb30bc400a3f80240713848dd5c3ab149e1ef7b57f7c339d96de853e4d9ee08e`.

Local evidence: `ta/hotpath-cpu.log`, `ta/hotpath-thread-profile-summary.txt`, `ta/generator-native*`, `ta/generator-checked-sizes-*`, `ta/checked-size-arithmetic*`, `ta/checked-size-cxx.log`, `ta/cpu-feature-diagnostic.log`, `ta/cpu-features-*`, `ta/cpu-init-order-diagnostic*`, `ta/cpu-sizes-build-check.*`, `ta/sizes-cpu-*`, and `ta/puma-sizes-cpu*`. The initial CPU-extension compilation failed because `RBOOL` is private; the corrected probe uses public `Qtrue`/`Qfalse` and has separate final receipts. An initial GCC compile against the entire Fil-C header tree failed on its existing `zandptr` use; the successful GCC control overlays only this patch onto pristine stock headers (`ta/checked-size-gcc-overlay.*`). Optional build-helper patch preparation was checked against the tested source byte-for-byte, deliberately stopping at an unavailable compiler; its nonzero preparation-smoke status is not a build pass.
