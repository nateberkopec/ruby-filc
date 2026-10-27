# Puma memory and performance acceptance

The requested target is **not met**: reliable, leak-free Ruby 4.0.9 / Fil-C Puma with at most a 5% penalty to memory and throughput/latency versus stock Ruby. This supersedes the earlier memory-only target; historical memory measurements cannot establish performance acceptance.

For the same application, workload and resources, every gate must pass: median and sampled-peak RSS at most 105% of stock; checked load throughput at least 95% of stock; and p50, p95 and p99 HTTP latency at most 105% of stock. The warmed-memory growth screens, successful responses and clean shutdown remain required. A memory saving does not compensate for a performance regression. Reliability and leak freedom require separate lifetime and sustained-workload evidence beyond these finite numeric screens.

## Workload and measurement

`probes/ruby/puma-memory-app.rb` serves a small order-processing application with Puma 8.0.2 and nio4r 2.7.5. Each POST parses JSON containing 50 line items and a note, calculates totals and a SHA-256 digest, and returns JSON. Five concurrent keep-alive clients check every response, including its unique request ID, items, total and digest. Puma runs one process with five threads; both JITs are disabled.

`measure-puma-memory.py` runs the HTTP client outside the measured Ruby process. It samples that process's Linux `smaps_rollup` every 100 ms, recording RSS, PSS, USS and swap. The primary acceptance metrics are median and peak RSS during the measured load/idle rounds. RSS includes native code, allocator metadata and thread stacks, not just Ruby heap objects. Client memory and file cache outside the Ruby process are not included.

The load generator uses one Python worker process per client, rather than threads sharing Python's GIL. Server and client CPU sets must be disjoint for acceptance. Throughput is the total checked measured request count divided by summed load-batch time; it excludes warmup, idle periods and diagnostic GC, but includes client request preparation, response validation and batch dispatch. HTTP latency runs from sending a prepared request through reading its full response, before JSON validation; first-request connection setup is included. Percentiles use nearest-rank selection over every measured request, not an average of per-round percentiles. Raw nanosecond latencies and batch CPU timings are retained in `.latencies.jsonl`.

This is a closed-loop, fixed-concurrency benchmark, not an open-loop production latency claim. The comparison rejects runs that consume more than 80% of assigned client CPU capacity in any round; this screens obvious load-generator saturation but does not prove the absence of every client-side bottleneck. Increase batch sizes for sustained-load measurements, and repeat matched runs before accepting results near a 5% boundary.

The default warmup is five batches of 1,000 requests. Ten measured batches follow, with two seconds idle between batches. No application-requested collection occurs during those rounds. One full GC after measurement is diagnostic only and is excluded from the acceptance metrics. Increasing `--rounds` and `--requests` extends the soak without changing the application.

The comparison also screens for growth: the median idle RSS in the last three rounds minus the median in the first three must not exceed 5% of the measured median. This is conservative: allocator warmup can fail it even on stock Ruby. A failure is not by itself proof of a leak, and a pass cannot prove leak freedom beyond the tested workload and duration.

Results include interpreter/shared-library and driver/workload hashes, server/client CPU affinity, cgroup memory/swap/CPU limits, Python and server versions, relevant GC environment settings, raw samples, server output and final mappings. The comparator rejects mismatched controls and older result files without current performance evidence. Schema 3 records and compares Ruby version, engine, patchlevel and platform explicitly. The full Ruby description remains provenance, not an equality gate: a patched Git worktree legitimately reports a different revision/date from a release archive. Schema 2 receipts must be rerun, not rewritten to synthesize those fields. `mise run test:puma-comparison` checks this distinction and the independent numeric gates. Both server shutdown and every HTTP response must succeed. Missing samples, sampler errors and workload failures are not converted into successful measurements.

## Run in a prepared Linux container

The two runtimes must have their own native gems compiled with their respective compilers. Do not reuse Fil-C extension binaries in stock Ruby. Both sides in this investigation use the same nio4r source patch; see [native-gems/README.md](native-gems/README.md).

`build-stock-runtime.sh` builds an unmodified, shared stock Ruby from the archive/version/checksum pinned by `example/Dockerfile`. It disables both JITs, selects ucontext, clears Fil-C compiler/library settings and installs into a new prefix. Its prerequisites are GCC/G++, make, a bootstrap Ruby, autoconf, bison and native development packages for OpenSSL, libyaml, zlib, libffi, readline, gdbm and GMP. The investigation built this control in the same Ubuntu container as the Fil-C runtime; it uses the system loader, not the Fil-C loader.

For example, inside a container with this repository mounted at `/work`, the verified Ruby archive already available, and those dependencies installed:

```sh
bash /work/port/build-stock-runtime.sh /work/tmp/ruby-4.0.9.tar.xz /opt/ruby-stock
env -u GEM_HOME -u GEM_PATH -u BUNDLE_APP_CONFIG /opt/ruby-stock/bin/gem install --local --no-document \
  /work/port/native-gems/nio4r-2.7.5-filc.gem /work/native-gems/cache/puma-8.0.2.gem
gem install --local --no-document \
  /work/port/native-gems/nio4r-2.7.5-filc.gem /work/native-gems/cache/puma-8.0.2.gem
bash /work/port/benchmark-puma-memory.sh /opt/ruby-stock/bin/ruby /usr/local/bin/ruby \
  /work/ta/puma-memory-comparison --rounds 30 --requests 2000 --idle 1 \
  --server-cpus 0-3 --client-cpus 4-7
```

Python 3 and Linux cgroup v2 are required. Run the container with a fixed CPU set and memory/swap limits. For the command above, make CPUs 0-7 available, with 4 GiB RAM and no additional swap; Ruby uses CPUs 0-3 and the external clients use CPUs 4-7. Historical memory-only measurements below used shared client/server CPU sets and the previous threaded load generator; do not compare their performance against the new process-based driver. The driver clears Fil-C gem and library overrides for stock Ruby, preserves the Fil-C environment for the other run, and records separate measurement/comparison exit statuses. The ignored gem/archive files above are local build inputs, not files provided by a fresh clone; the native-gem notes explain their preparation.

## First CPU-isolated performance comparison

Each runtime checks 70,000 responses: 10,000 warmup and 60,000 measured, with 30 measured batches and one-second idle intervals. The server has CPUs 0-3, clients have CPUs 4-7, and all runs use 4 GiB with no additional swap. No application GC is requested during load. These runs use the current process-based driver and must not be mixed with the earlier threaded-client receipts.

| Metric | Stock GCC Ruby | Default Fil-C (cache + RELR) | Plus shape-table chunks | Plus weak-map registry |
|---|---:|---:|---:|---:|
| Median RSS, KiB | 32,528 | 274,484 | 276,388 | 250,252 |
| Sampled peak RSS, KiB | 34,144 | 357,884 | 334,340 | 307,548 |
| Load throughput, requests/s | 9,155.0 | 2,136.8 | 2,123.0 | 1,691.9 |
| HTTP p50, ms | 0.399 | 2.068 | 2.089 | 2.376 |
| HTTP p95, ms | 0.902 | 4.323 | 4.292 | 6.867 |
| HTTP p99, ms | 2.338 | 6.921 | 6.854 | 9.649 |

Every Fil-C configuration fails every memory and performance ratio gate. Stock also fails the warmed-memory growth screen (+10.1%); Fil-C's screens pass. Client CPU use remains below 26% of its assigned capacity in every measured round. Stock consumes 6.37 server CPU-seconds over 6.55 load seconds, consistent with saturating its interpreter core rather than the client CPU allotment.

The weak-map candidate reduces median RSS by 9.5% relative to the shape-table-only run, but loses 20.3% of its throughput and worsens p95 latency by 60.0%. It is **not eligible for promotion** under the expanded target in its current form. Shape-table chunking has similar throughput to the default in this run, but its median RSS saving is not reproduced here; shorter-run collection timing is variable. None of these single comparisons establishes a repeatable 5% boundary pass or sustained-load reliability.

Raw timing/count/percentile/throughput consistency was checked against the saved per-request records. Receipts: `ta/puma-performance-baseline/`, `ta/puma-performance-shape-table.*`, `ta/puma-performance-registry.*`, and their comparison logs.

## Investigation

The first 3,500-request comparison used the existing stock `ruby:4.0.9` image and the released Fil-C image. Median RSS was 33,012 versus 682,954 KiB, and peak RSS was 34,304 versus 831,708 KiB. This established the failure but was not the final matched-container control.

The existing VM-stack and forwarding candidates were then built into the full runtime. The VM-stack lifetime reproducer changed from 99 retained strings to zero, confirming the intended library was loaded. It did not remove the large Puma footprint. An initial library-override attempt omitted the soname symlink and still loaded the baseline; those receipts are labeled `before-soname` and are not candidate evidence.

Stop-the-world FUGC did not materially improve the footprint. `FUGC_THRESHOLD_MULTIPLIER=1.01` reduced the short-run median to 270,308 KiB, still far above stock. Neither setting was adopted as a default or used to represent normal memory acceptance.

A native heap snapshot identified a 402,653,184-byte allocation rooted by `rb_shape_tree`: Ruby's ancestor lookup cache reserves its entire maximum capacity up front. Another allocation is the 20 MiB shape list. These are sparse virtual reservations on stock Ruby; Fil-C's collector accounts for the cache reservation as live memory, increasing its automatic-collection threshold. This is not evidence of 384 MiB of resident cache entries or a request-object leak.

The isolated `shape-cache-chunks-ruby-4.0.9.patch`, now included in the consolidated export, replaces only the Fil-C ancestor-cache reservation with lazily allocated 4,096-node chunks. Nodes retain stable addresses and IDs, and the existing maximum capacity, balancing algorithm and VM lock remain unchanged. Native/stock builds retain the original contiguous representation. No application GC calls, reduced cache limit or relaxed memory threshold are introduced.

With the same development runtime before and after this one-file change, an 11,000-request run changed median RSS from 759,248 to 311,728 KiB (59% lower), and peak RSS from 902,680 to 361,128 KiB (60% lower). The matched GCC control used 34,884 KiB median and 35,360 KiB peak. The modified runtime still failed the 5% target.

A longer run with 10,000 warmup requests followed by 60,000 measured requests checked all 70,000 responses on each runtime. Stock used 34,220 KiB median / 36,008 KiB peak; the chunked development runtime used 324,644 / 375,064 KiB. Fil-C's idle-growth screen was 4.3%; stock's was 6.3%, so stock did not satisfy that stability screen. Post-GC live-object counts were 30,772 and 31,674 respectively. These observations do not establish general leak freedom.

The clean exported build, without the separate VM-stack/forwarding candidates or GC tuning, also checked all 70,000 responses. It used 329,258 KiB median RSS and 386,724 KiB peak, versus the same stock control's 34,220 / 36,008 KiB: 9.62x median and 10.74x peak. Its idle-growth screen was 4.2%, post-GC RSS was 217,144 KiB, and post-GC live-object count was 31,721. The 105% comparison fails. Receipts: `ta/puma-memory-clean-long.*` and `ta/puma-memory-clean-comparison.*`.

The cache-only build's remaining gap was not just garbage awaiting reclamation: in the long run, the Fil-C `libruby` mappings alone occupied 53,356 KiB RSS, versus 4,472 KiB for stock `libruby`. That build's instrumented library by itself exceeded the entire stock process's 105% budget. The relocation improvement below removes some of this fixed overhead, but meeting the budget still requires more compiler/runtime footprint work, not merely clearing Ruby object references.

## Shape-cache validation and delivery

The isolated change is source commit `1a83325` on `filc-ruby-4.0.9-shape-chunks`, based directly on the released port baseline. Development-branch commit `b0ad29c` applies the same change alongside the separate stack/forwarding candidates. Only the isolated change was exported into the default Docker build.

- Normal and checked development builds each pass all 2,044 bootstrap tests (139.84 and 208.08 seconds).
- The existing standalone port regressions pass. The normal class/object/variable/Ractor selection passes 177 tests and 14,390 assertions. Normal builds do not expose `RubyVM::Shape`, so those debug-only tests did not run in that selection.
- A full checked runtime runs 70 shape tests and 401 assertions: zero failures and three errors from unsupported `GC.auto_compact=`. Rebuilding the same checked runtime without the cache change produces exactly the same three errors. No added failure identities, Fil-C safety errors or descriptor warnings appear in that comparison. The changed source was restored and rebuilt afterward.
- `probes/ruby/shape-cache-chunks.rb` passes on stock, normal, checked and clean-image runtimes. It exercises more than 380,000 cache nodes, chunk boundaries, compiled ivar reads, copying, removal/reinsertion, explicit GC and four concurrent Ractors.
- A fresh build from pristine Ruby plus the consolidated patch succeeds. Clean-image smoke, libc audit, existing cache/concurrency and GC-state checks, mapped-buffer checks, freshly compiled nio4r/Puma probes and the new shape-cache probe all pass.

Cache-only build image: `sha256:0a12bf4430d6d4140898e72786e5c5511da282973a0ea95dd86f160f406e7069`. Runtime image: `sha256:d582697cf5293db3fa457702b5f59cf365397405e089da291a67e3fec08d34b6`. These were the local `ruby-filc{,-build}:4.0.9` tags before relocation packing. Nothing was published. `mise run test` includes the new shape-cache system probe; the failing comparative memory gate remains a separate explicit command.

Consolidated patch SHA-256: `926e4388a264f9c9d608371ff18bf9c7d18bb8c499203455ed36f2877125cb6a`. Isolated patch SHA-256: `243646325611fb52def6d51deb970fe270610ea218c13fa9350384d41a67181c`.

Raw receipts are under the ignored `ta/` directory: `puma-memory-*`, `shape-chunks-*`, and `puma-memory-chunked-long/`. The full port remains experimental; memory improvements must not be read as full Ruby compatibility or acceptance of the separate VM-stack/forwarding candidates.

## ELF relocation packing

The cache-only `libruby` contains 843,010 relative relocations. Its `.rela.dyn` section occupies 20,458,992 bytes. ELF RELR packing reduces that section to 226,752 bytes and adds about 223 KiB of packed relocation entries, without removing machine code, safety checks or stack-trace metadata. This is about 19 MiB less mapped relocation data.

The Docker build now sets `XLDFLAGS=-Wl,-z,pack-relative-relocs` while configuring Ruby. Ruby applies this to its interpreter and shared library, but does not propagate it into extension `LDFLAGS` or `DLDFLAGS`. Using general `LDFLAGS` instead caused a clean build to fail when loading `monitor.so`: Fil-C's link omitted the `GLIBC_ABI_DT_RELR` dependency needed by the loader. A standalone reproducer and a proposed linker fix are in [the RELR report](upstream-filc-relr.md). The current build does not disable the loader check or apply the broken global setting.

Three fresh sequential runs each checked 70,000 HTTP responses, with the same workload, CPU set and 4 GiB/no-extra-swap limits:

| Metric, KiB | Stock GCC Ruby | Fil-C, cache chunks only | Fil-C, chunks + RELR |
|---|---:|---:|---:|
| Median RSS | 34,154 | 330,302 | 303,000 |
| Sampled peak RSS | 37,164 | 384,832 | 375,932 |
| Final measured `libruby` RSS | 4,472 | 53,620 | 34,128 |
| Diagnostic post-GC RSS | 36,744 | 214,332 | 186,872 |

The library's RSS falls by 19,492 KiB, consistent with the smaller relocation representation. Whole-process results also depend on collection timing; this one paired workload is not a promise of a fixed percentage improvement. No GC tuning or forced collection was added during the measured rounds.

The packed runtime still uses **8.872x stock median RSS and 10.115x stock peak RSS**, so the unchanged 105% gate fails. Its idle-growth screen is -7.8%; stock's is +8.5% and fails that screen. The packed run lasts about 66.6 seconds and ends with 31,723 Ruby live objects. These are not long-duration leak-freedom results. `libruby`, libc and libcrypto alone still exceed the stock application's total memory budget.

Validation:

- Fresh release-toolchain build, runtime smoke/libc audit, cache/concurrency/GC-state/buffer checks, native nio4r/Puma builds and their HTTP probes pass.
- `port/test-release.sh` passes on the actual runtime image, including the cache-chunk/Ractor probe, packed-interpreter/library checks and intentional native buffer-overflow detection.
- All 2,044 bootstrap tests pass in 145.29 seconds at the established 8 GiB test limit. An initial 4 GiB run fails the 1,000-Ractor case at `bootstraptest/test_ractor.rb:2514`, with one OOM kill. The unpacked cache-only build reproduces that same failure and one OOM kill at 4 GiB. Packing does not resolve this existing high-concurrency memory limit.
- Neither 4 GiB Puma measurement container records an additional OOM event or kill during its HTTP measurements.
- Version-lint CLI cases, Ruby release freshness and the working-tree secret scan pass. Fil-C release freshness is checked through the read-only GitHub Executor query (latest stable: v0.687), rather than the hook's direct GitHub request. Commit hooks are replaced by these explicit checks and the build/system checks above for this local change.

Current build image: `sha256:c987d779f7ea4c8749d0ace963f02f62840b33b425021539e69f9145365a46d4`. Runtime image: `sha256:c1783290f942b942f471a5dc53e9167e0c710858fc6d094d498517c8c209c6a4`. The local default version tags now include relocation packing. The consolidated Ruby patch hash is unchanged; the separate stack/forwarding candidates remain excluded. Nothing has been published.

Receipts: `ta/relr-core-build.*`, `ta/relr-runtime-checks.log`, `ta/relr-release-checks.log`, `ta/relr-bootstrap*`, `ta/relr-baseline-4g-*`, `ta/relr-*-events-*.log`, `ta/puma-memory-relr-control.*`, and `ta/puma-memory-relr-comparison/`. The final validation runner exits one because the memory acceptance comparison fails, not because its preceding runtime checks failed.

## Shape-table candidate

`shape-table-chunks-ruby-4.0.9.patch` is an incremental candidate on top of the current consolidated patch, not yet included in the default image. Source commit `e275504` on `filc-ruby-4.0.9-shape-table-chunks` contains only the shape-table change; the VM-stack/forwarding candidates remain excluded.

The Fil-C shape table now allocates 4,096-entry chunks rather than reserving all 20 MiB at startup. Atomic publication precedes shape-ID allocation. Chunks retain stable addresses and IDs, and the maximum capacity is unchanged. Shape enumeration uses IDs rather than walking a contiguous allocation. The debug exhaustion helper materializes the skipped chunks so its existing behavior remains available. Non-Fil-C builds retain contiguous storage.

Three sequential 70,000-request runs on CPUs 4-7, with 4 GiB RAM and no additional swap or GC tuning, produced:

| Metric, KiB | Stock GCC Ruby | Fil-C before | Fil-C candidate |
|---|---:|---:|---:|
| Median RSS | 35,028 | 305,750 | 272,164 |
| Sampled peak RSS | 37,520 | 355,688 | 346,412 |
| Diagnostic post-GC RSS | 35,916 | 185,376 | 165,068 |

The candidate lowers median RSS by 11% in this comparison, but still fails at **7.770x stock median and 9.233x stock peak**. Its idle-growth screen is -8.4%; stock's is +10.2% and fails. The final full GC is outside measurement and is not an alternative acceptance metric. These short runs do not establish leak freedom.

Validation completed before candidate publication:

- Normal and checked Fil-C builds each pass all 2,044 bootstrap tests, in 143.87 and 208.07 seconds. The checked build starts from the verified release archive plus the current consolidated and incremental patches.
- The normal class/object/variable/Ractor selection passes 177 tests and 14,371 assertions. The checked shape suite has 70 tests, 401 assertions, zero failures and the same three unsupported `GC.auto_compact=` errors identified in the previous cache-change investigation.
- A GCC build of otherwise pristine Ruby with the changed shape sources passes all 2,044 bootstrap tests and the shape-chunk probe. It is a branch-compatibility check, not the unmodified stock memory control.
- The system probe exercises about 48,000 shapes and more than 380,000 cache nodes, including concurrent chunk crossings. Its optional `--dump-shapes` mode checks that `ObjectSpace.dump_shapes` preserves every consecutive ID; the release-image runner now enables this mode. The existing `test_dump_shapes` also passes, with 264 assertions.
- Runtime integration and fresh native-gem checks pass on the candidate installation. A fresh default-image build incorporating this candidate remains a separate promotion step.

A diagnostic run before this candidate captured native heap graphs near 10,000, 100,000 and 250,000 requests. After explicit collections and synchronous scavenging, ordinary reachable payload was approximately 39-41 MiB, with 38-39 MiB of associated pointer storage. These are logical allocation sizes, not RSS, and exclude full accounting for special runtime objects. The 20 MiB shape reservation had companion pointer storage; multiple 1 MiB stack-sized allocations and weak-reference objects also remained. This supports investigating allocation representation rather than assuming that the application retains eight times as many Ruby objects. The diagnostic driver's final statistics failed because its 0.1-second idle periods sometimes contained no samples; its snapshots are diagnostic evidence, not a successful acceptance run.

Receipts: `ta/shape-table-*`, `ta/puma-memory-shape-table-*`, and `ta/puma-native-base-*`. The unchanged packed build's longer soak is still separate from this candidate's short comparison.

## Native weak-map registry candidate

`object-registry-weak-map-ruby-4.0.9.patch` contains source commit `45a59e3` on `filc-ruby-4.0.9-registry-compact`. It remains outside the default export. The following comparison applies it after the shape-table candidate, with no stack/forwarding changes or GC tuning.

Previously every Ruby allocation created a separate native weak-reference object and a 24-byte registry entry, with companion pointer storage. The candidate instead records the object and its heap-size class in Fil-C's native weak map. The collector removes dead entries during its normal weak-map census. Strong retention storage is created only for `GC.disable`; explicit collections and concurrent enable/disable transitions retain their existing protocol.

Native weak-map iterators hold strong snapshots. Directly yielding Ruby callbacks from one would let a suspended `ObjectSpace.each_object` enumerator pin unrelated objects. The candidate therefore converts the snapshot to temporary weak handles in a non-inlined helper before invoking callbacks, and releases the handle array through `rb_ensure`. This moves per-object weak-handle allocation to enumeration rather than every Ruby allocation. The new system probe catches the naive implementation: plain/suspended counts are 2/100 there, versus 2/2 on both the baseline and corrected candidate, and 0/0 on stock. It guards against added enumeration retention, not every existing port retention issue.

Fresh sequential measurements on CPUs 4-7, with 4 GiB/no-extra-swap limits and 70,000 checked requests per run:

| Metric | Stock GCC Ruby | Fil-C shape-table candidate | Fil-C plus weak-map registry |
|---|---:|---:|---:|
| Median RSS, KiB | 34,340 | 281,884 | 234,376 |
| Sampled peak RSS, KiB | 38,164 | 335,416 | 294,892 |
| Diagnostic post-GC RSS, KiB | 33,736 | 184,840 | 146,148 |
| Elapsed seconds, including idle/diagnostic phases | 43.00 | 66.58 | 76.35 |

The registry change lowers median RSS by 16.9% and peak RSS by 12.1% in this comparison, but the run takes longer. It still fails the unchanged gate at **6.825x stock median and 7.727x stock peak**. Both short-run growth screens pass: stock +2.7%, Fil-C -10.1%. No collection or scavenging calls were added during measured rounds.

Validation: normal and checked builds pass all 2,044 bootstrap tests (135.61 and 169.72 seconds); the six GC-state/concurrency/fork scenarios pass; runtime integration, newly compiled native gems, Puma HTTP checks, shape enumeration and the new lifetime probe pass. The existing GC/ObjectSpace selection runs 91 tests: both baseline and candidate have the same eight failures, 14 errors and two skips, with no new failing identities, safety errors or descriptor warnings. This is not full Ruby compatibility.

During development, `make` failed to rebuild `gc.o` after changes to `gc/filc/filc.c`. The default consolidated patch now includes the missing dependency, independently of either memory candidate. The earlier `registry-weak-snapshot` and `registry-isolated-snapshot` attempts still loaded the original prototype and are not corrected-candidate evidence. Corrected normal-library SHA-256: `5893407d41df75b595bc81f40375e4c451706e8113b66ea7d662934fbda6c6ec`.

Receipts: `ta/registry-corrected-*`, `ta/registry-checked-*`, `ta/registry-runtime-checks.*`, `ta/registry-*-ruby-tests.*`, `ta/registry-lifetime-*`, and `ta/puma-memory-registry-*`.

A separate lifetime issue remains: clearing a 100-element array leaves 32 marker objects reachable in both the baseline and registry candidate; explicitly filling it with nil before clearing leaves two. Stock retains zero in either case. The array's unused capacity still contains references visible to Fil-C. This has not been fixed by changing the object registry. Receipt: `ta/array-clear-lifetime.log`.

## Array#clear retention fix candidate

`array-clear-ruby-4.0.9.patch` contains source commit `eb0e109` on `filc-ruby-4.0.9-array-retention`. It changes only `array.c` and also applies to the default exported source; measurements below use the shape-table plus weak-map build. It remains outside the default export.

Two independent references survive an ordinary clear: entries in the retained backing-buffer capacity, and pointer capabilities in the array object's storage. Fil-C's compiler emits scalar integer stores without clearing prior pointer metadata. Reusing the first two inline element slots as heap length/capacity therefore leaves the original two objects reachable, even when the backing buffer has been filled with nil. A shared array can also retain its former backing buffer through the now-unused inline representation.

The fix uses Fil-C's explicit `zmemset` to clear the kept buffer and inactive object storage, then restores the heap pointer and capacity. It does not free another array's shared storage, alter capacity policy, clear the object's header/private GC fields, or change non-Fil-C behavior. The ordinary compiler-optimizable memset is deliberately not used for clearing capabilities.

`probes/ruby/array-clear-lifetime.rb` checks empty, embedded, heap, expanded-to-heap and shared arrays in separate Ruby processes. It verifies collection of all removed marker objects, sibling contents, instance variables and reuse. The old build fails on retained objects; the candidate and stock release all markers. Other shrinking operations and pointer/scalar union transitions still need auditing; this is not general leak-freedom evidence.

Validation: normal and checked builds each pass all 2,044 bootstrap tests and the Array/Ractor selection (491 tests, 22,215 assertions, zero failures/errors, 16 skips). The five lifetime cases pass on both builds and on a GCC-built miniruby. The initial GCC probe launcher failed because miniruby cannot load Open3; the cases were rerun directly after making the parent-only standard-library dependencies conditional. A broader GC/ObjectSpace selection remains red on both before/after libraries: 157 tests, 11 failures and 14 errors, with identical failure identities and no safety errors or descriptor warnings.

In the same CPU-isolated 70,000-request workload, median RSS changes from 250,252 to 223,688 KiB and sampled peak from 307,548 to 304,532 KiB. Load throughput is 1,691.9 versus 1,677.0 requests/s; p50/p95/p99 latency changes from 2.376/6.867/9.649 to 2.426/6.755/9.263 ms. This single pair does not establish a repeatable performance difference. The combined candidate still fails every ratio gate: 6.877x stock median RSS, 8.919x peak RSS, 18.3% of stock throughput and 6.080x stock p50 latency. It does not make the weak-map registry eligible for promotion.

Receipts: `ta/array-clear-*` and `ta/puma-performance-array-clear.*`. Validation of this fix independently of the slower registry candidate remains pending.

## Longer matched soak

The unchanged cache-chunks plus RELR build, without either newer candidate, completed 4,010,000 checked requests in 4,388.76 seconds. Stock completed the same count in 2,702.95 seconds. Neither run added a cgroup OOM event or kill.

| Metric, KiB | Stock GCC Ruby | Fil-C |
|---|---:|---:|
| Median RSS | 66,396 | 276,660 |
| Sampled peak RSS | 86,068 | 359,416 |
| Diagnostic post-GC RSS | 75,316 | 165,832 |

Fil-C's idle RSS settles around 214-217 MiB after the initial portion of the run; the growth screen is -17.8%. Stock grows substantially and fails its screen at +61.5%, despite ending with the same 30,768 live Ruby objects as the short controls. Allocator retention and native buffers need separate investigation; this observation alone does not identify a leak. The memory comparison still fails at 4.167x median and 4.176x peak. Do not mix this longer stock baseline with a newer candidate's short-run result. Finite stability here does not establish general leak freedom.

Receipts: `ta/puma-memory-hour-*`, including hashes, raw samples, mappings, cgroup events and comparison status.

## Fresh amd64 build and broader array-retirement candidate

On the Debian 13 amd64 host, fresh Ruby 4.0.9 builds use GCC 14 and the checksum-verified optfil 0.687 archive. Both disable JITs and use ucontext. Fil-C uses the current consolidated patch and packed interpreter/library relocations, with none of the separate shape-table, weak-map, stack or forwarding candidates. Matching nio4r/Puma native extensions were rebuilt; the patched nio4r gem reproduces its recorded SHA-256. Both native-gem probes pass. Stock passes all 2,044 bootstrap tests. This is a host-build validation, not validation of the default amd64 Dockerfile or the full Ruby suites.

The first out-of-tree Fil-C attempt failed because quoted includes selected stale release-generated VM headers beside the source instead of regenerated headers in the build directory. An in-tree build completed. Its Git-derived Ruby description differs from stock; the first comparison rejected that difference. The schema-3 comparison above fixes the identity check without changing a numeric threshold, and both runtimes were measured afresh. The failed attempts remain recorded rather than being relabeled as passes.

Each subsequent runtime checked 70,000 responses (10,000 warmup plus 60,000 measured), with 30 rounds of 2,000 requests and one-second idle intervals. All ran sequentially in the same Debian container with 4 GiB, no swap, server CPUs 0-3 and client CPUs 4-7. The container mounts the host `/usr` read-only for its native libraries/Python, the development workspace at its absolute path, and the matching toolchain at `/opt/fil`. No other builds ran during these comparisons. No application collection or scavenging occurred during measured rounds.

| Metric | Stock GCC Ruby | Default Fil-C | Array-retirement candidate |
|---|---:|---:|---:|
| Median RSS, KiB | 36,264 | 190,064 | 189,154 |
| Sampled peak RSS, KiB | 39,808 | 196,920 | 194,852 |
| Load throughput, requests/s | 3,468.1 | 785.4 | 792.3 |
| HTTP p50, ms | 1.190 | 5.836 | 5.809 |
| HTTP p95, ms | 2.403 | 11.279 | 11.151 |
| HTTP p99, ms | 3.891 | 14.787 | 14.649 |

Every Fil-C numeric ratio still fails. Stock also fails the growth screen (+19.7%); both Fil-C growth screens pass. Maximum client CPU utilization is below 28% on stock and 7% on Fil-C. The small before/after differences are not evidence of a repeatable performance improvement or compliance with the 5% goal. Both runs check every response and shut down cleanly; these short runs do not establish sustained-run reliability or general leak freedom.

`array-shrink-ruby-4.0.9.patch` is a new **isolated candidate**, applied directly after the consolidated port. It replaces rather than stacks on the earlier clear-only candidate. Two helpers retire removed elements and inactive array-object storage using Fil-C's capability-clearing `zmemset`. The patch clears embedded storage when switching to a heap representation, clears inactive storage on reset/re-embedding, and retires removed slots across shrinking paths. Shared buffers are not cleared through a non-owning array; capacity policies, object headers, private GC fields and non-Fil-C behavior are retained. Retirement work follows the number of removed slots, rather than rescanning the entire capacity after each pop.

The fresh baseline fails 41 of the 48 cases in `array-shrink-lifetime.rb`; stock passes all 48. The cases cover `pop`, `shift`, `delete_at`, `select!`, `reject!` and `replace`, partial/full removal, and small, larger embedded, heap and expanded-to-heap storage histories. They check exact survivors, removed-object reclamation, instance variables and reuse after retiring the allocating thread. The candidate passes all 48 plus the five existing clear/sharing cases. Normal Fil-C passes all 2,044 bootstrap tests and the Array/Ractor selection (491 tests, 22,215 assertions, zero failures/errors, 16 skips). GCC with the candidate's `array.c` also passes all 2,044 bootstrap tests; the unmodified stock installation remains the benchmark control. An independent full checked build from the verified archive and both patches is running; the candidate is not promoted into either consolidated export.

Candidate patch SHA-256: `f89aacac15b6eeb0f52a84ab649f76e41d6010fe56380a640ce10cefee9c8bd6`. Normal candidate library SHA-256: `442ba6503eeb7b1f26d1b25e3d09345755dda56c1db603fc044b10e45a2e670e`. Receipts: `ta/build-amd64-*`, `ta/check-amd64-filc.*`, `ta/bootstrap-amd64-stock-corrected.*`, `ta/array-shrink-*`, `ta/puma-amd64-baseline/`, and `ta/puma-amd64-array-shrink*`.

`puma-order-hotpaths.rb` adds checked, non-HTTP diagnostics for parsing, transformation, hashing and serialization. Its optional phase argument permits separate profiles. A 20,000-iteration Fil-C diagnostic using the native sampling profiler completes and highlights interpreter dispatch, JSON work and hash/string comparisons as well as allocation. The profiler reports inclusive counts across recursive frames and threads, including waiting threads; its percentages are not exclusive CPU shares. Diagnostic results must not be substituted for HTTP throughput/latency or memory acceptance. Receipt: `ta/puma-order-filc-profile.*`.

## Upstream GC accounting proposal

`probes/c/mmap-gc-pressure.c` isolates the sparse-reservation problem without Ruby. It allocates and immediately frees about 195 MiB of small objects. With no reserved mapping, three runs peak at 16,236-84,760 KiB and complete 8-180 automatic cycles. Keeping a 384 MiB mapping alive while touching one byte produces 217,648-223,124 KiB peaks and only 0-1 automatic cycles. The starting peaks remain below 18 MiB.

The source and threshold logs show why: the surviving reservation raises the default 1.5x threshold, granting about 192 MiB of additional allocation headroom. This is not evidence of a permanent leak. The [upstream proposal](upstream-filc-mmap-gc.md) asks about separating reserved size from the survivor footprint used to set additional headroom, while preserving capability safety, mapping lifetime and pressure from new allocations. No speculative collector policy change has been made locally. The shortened reports were posted with approval as [#351](https://github.com/pizlonator/fil-c/issues/351) and [#352](https://github.com/pizlonator/fil-c/issues/352).
