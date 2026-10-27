# Compact weak-reference vector for Ruby objects

This amd64 candidate reduces registry storage without the native hash-map lookup cost of the earlier weak-map candidate. It is isolated from the consolidated exports. The Puma goal remains unmet; the focused checks below are not a full compatibility or leak-freedom verdict.

## Representation and invariants

`object-registry-vector-ruby-4.0.9.patch` replaces each 24-byte registry record (`weak`, `retained`, `heap_id`) with one 8-byte weak-reference pointer. It still creates a native weak-reference object for each Ruby object. It does not replace Fil-C allocation, disable safety checks, or change Ruby object layouts. The registry array and its companion pointer storage shrink; the per-object weak-reference cost remains.

The allocation-time aggregate record assignment disappears. Per-heap allocation counters retain their original update point. Live heap statistics derive the size class from the existing object-slot-size and heap-ID helpers instead of storing an extra byte in every record. This adds work to statistics enumeration, not to ordinary allocation.

Strong retention uses a separate pointer array only while Ruby GC is logically disabled:

- Retained slots have the same indices as weak slots. Compaction moves both arrays together and clears vacated capability storage with `zmemset`.
- Disabling GC reserves enough slots before changing the logical state. Every allocation while disabled maintains capacity for the entire registered prefix, including during outstanding explicit requests.
- Explicit collection clears roots but retains storage. Its final request can restore roots without allocating or raising after unlinking itself.
- Restoring roots reads each weak reference before replacing its corresponding existing strong root. Clearing all roots first would briefly expose post-request allocations to a concurrent native collection; an initial implementation with that ordering was stopped during build and corrected before final validation.
- Enabling GC releases retention storage. Full/immediate registry trimming can shrink both arrays. Enumeration still prevents compaction, retains its original prefix limit, and does not pin unrelated objects.
- Registry locking, request ordering, fork synchronization and the GC-count protocol are unchanged. Reallocation failures unlock and raise, rather than returning a success-shaped fallback. Allocation-failure injection has not been run.

The patch applies directly to the consolidated baseline and is an alternative to, not an addition to, `object-registry-weak-map-ruby-4.0.9.patch`.

## Validation

The normal candidate builds on the prior `-g0` + scalar checked-arithmetic + CPU-initialization configuration. Its installed control and standard extensions remain unchanged. It passes **2,044 bootstrap tests**.

Both control and candidate pass the existing weak ObjectSpace-enumerator lifetime, GC accounting/disable/hook/stress probes, and all six `review-gc-state.rb` scenarios: concurrent enabling, disabled counts, overlapping requests, atomic transitions, enable during overlap, and fork accounting.

The new `object-registry-retention.rb` probe exercises all five heap-size classes over three rounds. It verifies live-class accounting and 10,000 weakly held objects across native collections while Ruby GC is disabled; explicit Ruby collection must reclaim them without enabling GC. Another 10,000 allocations must remain retained after collection, then be reclaimed after enable. Every round requires zero remaining test objects after reclamation. Native cycle numbers must advance while the logical Ruby GC count stays unchanged for native-only cycles.

`FilcCacheHeap.collect` deliberately requests a fresh native cycle without releasing Ruby's disabled-GC roots. This is intrusive diagnostic tooling, never an acceptance-round operation. The first test draft incorrectly assumed `String.new(capacity:)` used embedded slots; the corrected fixture uses string multiplication and verifies the reported embedded slot size. A subsequent draft retained one object on the control when statistics and reclamation ran on the main thread. The final probe ends the helper thread that inspects objects before testing reclamation, separating diagnostic-stack lifetimes from registry retention. This does not establish that other stack-lifetime issues are fixed.

Broader GC/ObjectSpace/Ractor selections are **not green**:

| Configuration | Tests | Assertions | Failures | Errors | Skips |
|---|---:|---:|---:|---:|---:|
| Prior control | 175 | 65,764 | 12 | 14 | 4 |
| Vector candidate | 175 | 65,772 | 12 | 14 | 4 |

The complete failure/error name lists match. The comparison driver's zero status means the focused probes and comparison procedure finished; both broader-suite statuses remain nonzero. They include missing GC interfaces/statistics and unsupported default-collector age/write-barrier fields. The earlier candidate ObjectSpace/Ractor-only selection has 121 tests, 65,413 assertions, three failures and two skips; those three failures are also in the control. These are existing limitations, not passes or exclusions from a full compatibility claim.

An independently sourced checked tree combines the vector patch with the previously validated array/table retirement patches, without the arithmetic/CPU patches or `-g0`. With `VM_CHECK_MODE=1` and `VM_DEBUG_BP_CHECK=1` (also enabling Ractor checks), it passes **2,044 bootstrap tests** and **862 Array/Hash/Set/Ractor/C-table tests, 35,438 assertions, zero failures/errors, 27 skips**. It also passes all three new retention rounds, GC-count checks and all six concurrent/fork scenarios. The initial checked selection failed because `-test-/st` was parsed as an option; the corrected `./test/-ext-/st` selection has a separate successful receipt.

## Matched Puma measurements

Six completed matched runs alternate stock, prior combined control, vector candidate, vector candidate, control, stock. All use the unchanged 70,000-response workload, 4 GiB/no swap, server CPUs 0-3 and clients 4-7. Both Fil-C configurations select the same previously built standard extensions. Only their Ruby library differs. No builds, GC overrides or application collection/scavenging run during acceptance measurements.

| Run | Median RSS, KiB | Peak RSS, KiB | Requests/s | p50, ms | p95, ms | p99, ms |
|---|---:|---:|---:|---:|---:|---:|
| 1 stock | 37,468 | 40,792 | 3,490.3 | 1.191 | 2.394 | 3.505 |
| 2 control | 176,332 | 182,244 | 812.2 | 5.655 | 11.102 | 14.352 |
| 3 vector | 169,528 | 187,832 | 797.2 | 5.767 | 11.034 | 14.342 |
| 4 vector | 171,040 | 177,300 | 811.2 | 5.684 | 10.933 | 14.166 |
| 5 control | 176,620 | 184,988 | 801.9 | 5.724 | 11.076 | 14.558 |
| 6 stock | 36,004 | 39,804 | 3,475.2 | 1.186 | 2.449 | 3.915 |

The candidate reduces mean median RSS about **3.5%** relative to the two controls. Its peaks do not consistently improve: the first exceeds both controls. Mean throughput is about **0.4% lower**, with the ordering reversed in the second pair; these runs do not establish a repeatable throughput improvement or regression. The recorded GC count rises from 1,410 in each control to 1,451/1,452. The result is a modest median-memory reduction, not a solution to the large execution overhead.

Every stock-relative numeric gate fails. The first candidate uses **4.525x stock median RSS**, delivers **22.8% of stock throughput**, and has **4.842x stock p50 latency**. Both stock warmed-growth screens fail (+20.8%/+21.3%); both vector screens pass (-4.0%/-1.9%). Client utilization stays below 27%. All checked responses and shutdowns succeed. The driver exits zero; comparators correctly exit nonzero. Finite runs and focused reclamation checks do not establish sustained reliability or general leak freedom. The candidate is not promoted.

## Remaining resident-library constraint

The second candidate's mapping snapshot is taken after load and before the explicit diagnostic GC request. `libruby`, `libcrypto` and Fil-C libc alone account for **23,976 + 14,560 + 11,628 = 50,164 KiB RSS**. These are three distinct mapping groups, including their resident code/data/metadata, not additional amounts to add to process RSS. That subtotal already exceeds the final stock run's entire peak allowance of **41,794 KiB** (39,804 x 1.05), before counting any Ruby heap, stacks or other libraries. Further registry-only reductions cannot make this unchanged mapped-library footprint fit the goal. Reducing native-library residency is therefore required as well as fixing allocation/execution overhead; this end-of-load snapshot is not a replacement for median/peak measurements.

## Reproduction and provenance

For the normal configuration, use a new directory and the existing build-only helper:

```sh
bash port/build-nodebug-candidate.sh tmp/ruby-4.0.9.tar.xz tmp/registry-vector-build \
  tmp/install-stock/bin/ruby tmp/install-filc \
  port/checked-size-arithmetic-ruby-4.0.9.patch \
  port/cpu-feature-init-ruby-4.0.9.patch \
  port/object-registry-vector-ruby-4.0.9.patch
```

Select an isolated copy of its `libruby` using `LD_LIBRARY_PATH`; do not replace the installed controls. For the measured pair, `RUBYLIB` points to the same `tmp/sizes-cpu-stdlib` tree for both Fil-C configurations. Build `probes/c/cache-heap/` with the matching Fil-C Ruby, then pass its directory with `-I` when running the retention probe. Stock Ruby is not expected to provide this native-collector API.

Identities (SHA-256):

- Vector patch: `be307931d3686cd46647e3e1d4c0551b45c3df81bbfbfe81fd03ace10f3cb0bf`.
- Normal vector library: `d347369c045b081e9d7287de53e069d15513bd2bda5a57b4efd051b65cc54087`.
- Prior combined control: `03aef2370d01e656013a206b8e701c5a630581d552325fe10551e0f6a1752021`.
- Checked array/table/vector library: `eea2215269af3c46fee72de87c03d99fc596b68739fe52b47dde91891a72d968`.

The checked tree was already built from the verified archive; its pre-vector adapter was byte-identical to the baseline and its original library is preserved in `tmp/array-hash-checked-before-registry/`. The final adapter files in both source trees match byte-for-byte. Normal build/bootstrap and the independent checked validation have separate logs; a failed broader suite does not become a pass because its failure names match the control.

Local evidence: `ta/compact-registry-*`, `ta/registry-vector-checked*`, `ta/puma-registry-vector*`. The original interrupted build, initial probe failures, initial checked-run argument failure and successful corrected receipts are retained separately.
