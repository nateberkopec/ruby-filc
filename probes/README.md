# Runtime probes

These are standalone system-level programs, not a single all-green test suite. Some verify fixed regressions, some reproduce unresolved failures, and others only print measurements. They keep their original lifetime assertions, collection counts and workload sizes.

## Ruby

Run from the repository root, using the Ruby build being investigated. For example:

```fish
docker run --rm --memory=8g --memory-swap=8g \
  --mount type=bind,src=(pwd),dst=/work,readonly \
  ruby-filc:4.0.9 ruby /work/probes/ruby/callcache-cme-lifetime.rb dispatch
```

| Files under `ruby/` | Purpose |
|---|---|
| `callcache-*`, `protected-callcache.rb` | Weak class/method-entry caches, active-call lifetime and callback invalidation |
| `metaclass-publication.rb`, `subclasses-concurrent-gc.rb` | Concurrent class construction and enumeration |
| `vm-stack-*` | Retired VM-stack storage; requires the separate candidate for its expected lifetime results |
| `tail-forward-minimal.rb` | Known failure when tailcalling into an argument-forwarding method; `plain` is the non-tail control |
| `review-*`, `gc-*`, `finalizer-churn.rb` | Collection state, retention, accounting and finalizer behavior |
| `buffer-*` | Mapping/resizing behavior; private-file growth remains an unresolved failure |
| `ractor-port-pressure.rb`, `ractor-port-phases.rb`, `ractor-select.rb` | Ractor behavior and memory pressure; port pressure has exceeded the 8 GiB limit |
| `allocation-pressure.rb`, `class-retention*.rb`, `struct-retention.rb`, `weakmap-gc-phases.rb` | Allocation/lifetime measurements, not broad correctness verdicts |
| `nio4r.rb`, `puma.rb` | Native-gem probes; first build matching native extensions as described in `port/native-gems/README.md` |
| `puma-memory-app.rb` | Order-processing HTTP app driven and measured by `port/benchmark-puma-memory.sh`; the memory, throughput and latency targets are still unmet |
| `puma-order-hotpaths.rb` | Checked parse/transform/digest/generate diagnostics without HTTP; records main-thread/process CPU and wall time, accepts iteration count and phase (`all` by default), and is not an acceptance benchmark |
| `checked-size.rb` | Boundary, random and constant-factor size arithmetic against arbitrary-precision results; checks exact overflow errors using the matching `c/checked-size/` extension |
| `object-registry-retention.rb` | Fil-C-only, intrusive native collection across all five object-size classes; checks disabled-GC retention, explicit/enable reclamation and accounting using `c/cache-heap/` |
| `cpu-features.rb` | x86-64 SSE2 detection before explicit initialization and initialization idempotence, using `c/cpu-features/`; catches the baseline Fil-C startup defect |
| `array-clear-lifetime.rb` | Checks removed-object collection, sharing, instance variables and reuse after Array#clear; requires an array-retirement candidate and intentionally fails on the default Fil-C build |
| `array-shrink-lifetime.rb` | Checks removed and surviving objects across six shrinking operations and four storage histories; requires `port/array-shrink-ruby-4.0.9.patch`, which also covers clear and replaces (not stacks on) the earlier clear-only candidate |
| `hash-delete-lifetime.rb`, `set-delete-lifetime.rb` | Exact removed/surviving object lifetimes across deletion, filtering, clearing and replacement; see the separate [table-retirement candidate](../port/table-retirement.md) |
| `st-table-lifetime.rb`, `table-compaction-lifetime.rb` | Direct C-table lifetime and vacated compaction slots; build `c/st-table-lifetime/` with the matching Ruby and add its build directory with `-I` |
| `table-delete-during-iteration.rb`, `st-table-iteration-delete.rb` | Current-entry deletion, clear and nested deletion with colliding Hash/Set keys; the native-table probe checks deletion/reinsertion before returning `ST_DELETE`, requires the helper extension and caught a candidate-only regression |
| `string-hash-compare.rb` | Direct string hash comparator versus `String#eql?` across lengths, mutations and encodings; build `c/string-hash-compare/` and add its directory with `-I`; the short-string candidate is experimental, not promoted |
| `filc-heap-snapshot.rb` | Native heap graph, process status and mappings after explicit collection/scavenging; load libraries with `-r`, build `c/cache-heap/`, and pass an output prefix; diagnostic only, never an acceptance workload |
| `object-registry-lifetime.rb` | Compares unrelated-object retention with and without a suspended ObjectSpace enumerator; catches whole-heap retention by a strong iterator snapshot |
| `shape-cache-chunks.rb` | Shape/cache chunk boundaries, ivar lookup/copy/removal, GC and concurrent Ractor construction; `--dump-shapes` also verifies complete, consecutive IDs through ObjectSpace |
| `fiddle.rb`, `ioctl.rb`, `timezone.rb`, `scheduler-stress.rb` | Focused runtime integration checks |

The release-image regression runner is `example/regressions.sh`. The candidate retirement matrix is `port/check-vm-stack-retirement.sh`, which accepts a Ruby executable and an output prefix. Runners under `port/` may assume the development container's `/work` and `/compiler` layout.

## C

`c/` contains small compiler/runtime reproductions and native heap-dump helpers:

- `setjmp-*`: allocation pressure, parallel calls, OOM and scavenging.
- `mremap-support.c`: supported mapping operations.
- `mmap-gc-pressure.c`: malloc/free churn with and without a sparse 384 MiB mapping; measures the unresolved FUGC headroom problem described in [the upstream proposal](../port/upstream-filc-mmap-gc.md).
- `relr-dlopen.c`: builds both a tiny shared library and its loader; packing the library reproduces a missing glibc ABI dependency in Fil-C 0.687. Commands and expected failure are in [the upstream report](../port/upstream-filc-relr.md).
- `binding/`: dynamic-loader symbol binding.
- `cache-heap/`, `vm-stack-heap/`: native heap/root inspection helpers for matching Ruby/Fil-C builds. `FilcCacheHeap.dump(fd)` writes the native heap graph; `FilcCacheHeap.address(object)` reports an object's address; `FilcCacheHeap.scavenge` synchronously releases reclaimable allocator memory; `FilcCacheHeap.collect` requests and waits for a fresh native cycle without releasing Ruby's disabled-GC roots. For diagnostic reclamation snapshots, collect first and then scavenge. These intrusive operations are not part of the normal Puma memory acceptance workload.
- `string-hash-compare/`: Ruby extension exposing the real `rb_str_hash_cmp` result for the corresponding Ruby probe. Build with the selected Ruby's `extconf.rb` and `make` in a separate ignored build directory.
- `st-table-lifetime/`: Ruby extension wrapping direct `st_table` APIs without Hash's automatic post-deletion compaction. Its stock mark callback traces only live entries, allowing matched stock/Fil-C object-lifetime tests. See [build commands and results](../port/table-retirement.md).
- `checked-size/`, `cpu-features/`: native probes for [scalar checked arithmetic and CPU-feature initialization](../port/checked-arithmetic-cpu-init.md). Build with each matching Ruby's `extconf.rb`/`make`, then use `-I` to load the extension.
- `checked-access.c`: valid memory/indirect-call control plus intentional bounds, freed-memory, read-only and argument-count violations. `port/check-filc-debug-flags.sh` compares rejection with `-ggdb3` and `-g0`; see [the debug-information experiment](../port/filc-debug-info.md).
- `timezone.c`: timezone integration.

Compile with the same Fil-C compiler/runtime as the Ruby being investigated. GCC controls must use ordinary system libraries instead. Do not load a helper built against another Fil-C ABI into Ruby.

Historical results are in `port/STATUS.md`; new local logs belong in the ignored `ta/` directory. A script finishing is not evidence that each recorded test or subprocess passed.
