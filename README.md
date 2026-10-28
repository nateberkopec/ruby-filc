# Ruby 4.0.9 with Fil-C: closed experiment

**Status: closed. The goal was not reached.**

This repository is the record of an experiment that ported Ruby 4.0.9 to [Fil-C](https://github.com/pizlonator/fil-c) 0.687, a memory-safe C/C++ implementation, using glibc and Fil-C's FUGC collector. The goal ([`GOAL.md`](GOAL.md)) was to run Puma reliably and without leaks, with all Fil-C safety checks kept, within 5% of stock Ruby 4.0.9 on memory, throughput and latency. None of the numeric targets were met. The final analysis concludes that they can't be met with the released Fil-C compiler and runtime, so work has stopped.

The port runs real programs, including plain and TLS Puma, nio4r, OpenSSL and JSON. It has never passed Ruby's full test suites and is not a drop-in replacement for ordinary Ruby. Nothing here should be used in production.

## Outcome

Final matched amd64 measurements (means of two runs each), from the best combined candidate ([details](port/puma-combined-candidate.md)): a checked JSON order-processing Puma workload, 60,000 measured requests per run, with the server and the load generator on separate CPUs.

| Metric | Stock GCC Ruby | Best Fil-C candidate | Goal | Result |
|---|---:|---:|---:|---|
| Median RSS | 42,464 KiB | 142,582 KiB (3.36x) | ≤ 1.05x | Fail |
| Sampled peak RSS | 45,396 KiB | 150,022 KiB (3.30x) | ≤ 1.05x | Fail |
| Throughput | 3,303 req/s | 811 req/s (24.5%) | ≥ 95% | Fail |
| p50 latency | 1.21 ms | 5.73 ms (4.72x) | ≤ 1.05x | Fail |
| p95 / p99 latency | 2.94 / 4.04 ms | 10.88 / 13.58 ms | ≤ 1.05x | Fail |
| Server CPU per request | 0.296 ms | 1.78 ms (6.0x) | | |

Every response was checked, and every run shut down cleanly. Focused probes show that the objects they targeted are reclaimed. These finite runs do not establish general leak freedom.

## Why it was closed

The [feasibility analysis](port/goal-feasibility.md) found that the gap comes from code Fil-C generates itself, not from Ruby-port inefficiencies that patches could remove:

- **CPU.** On small fixed interpreter workloads, Fil-C executes 8-16x as many machine instructions as stock. A `while` loop that allocates nothing takes about 1,700 instructions per iteration, versus 126. Pushing one integer onto the VM stack takes about 100 fast-path instructions of bounds checks, capability (pointer metadata) loads and stores, collector barriers and frame bookkeeping. In a Puma profile, about 30% of samples are the collector and 46% are in the Fil-C runtime library. No Ruby function is above about 10%.
- **Memory.** In end-of-load snapshots, the Fil-C process's file-backed mappings (mostly library code) alone are 58,088 KiB resident. Stock's whole process is 44,972 KiB, so the 105% limit is 47,221 KiB. Fil-C's `libruby` code section is 26.6 MB, versus 4.0 MB for stock.
- **Remaining source-level work is too small.** Port changes delivered gains of a few percent to about 20% each. Examples include on-demand shape-cache chunks, packed relocations, `-g0`, array and table retirement, registry compaction and packed OpenSSL. A different instruction-dispatch mode and removing the redundant stack protector didn't help materially. The largest remaining fix identified is the dispatch-loop work described in the analysis, bounded at a few percent of Puma CPU.

Closing the gap would require new Fil-C compiler and runtime capabilities, such as much cheaper checks or smaller generated code. That was outside this experiment's scope.

## What the experiment produced

- A 143-file Ruby 4.0.9 port patch ([`ruby-4.0.9-filc.patch`](ruby-4.0.9-filc.patch)). It covers VALUE capability handling, a Fil-C GC implementation on FUGC, weak call caches, concurrency fixes for collection during class, metaclass and subclass operations, and native-extension fixes.
- Isolated, measured candidate patches in [`port/`](port/README.md) that are not part of the default build: array, hash and table retirement, the object-registry vector, shape-table chunks, checked arithmetic and CPU-feature initialization, short-string equality, and VM-stack retirement.
- A matched Puma memory, throughput and latency benchmark with enforced gates: [`port/measure-puma-memory.py`](port/measure-puma-memory.py), [`port/compare-puma-memory.py`](port/compare-puma-memory.py) and [`port/puma-memory.md`](port/puma-memory.md).
- An instruction-count comparison: [`port/measure-interpreter-overhead.sh`](port/measure-interpreter-overhead.sh).
- Standalone regression probes and reproducers in [`probes/`](probes/README.md).
- Upstream Fil-C reports on [sparse-mapping GC headroom](https://github.com/pizlonator/fil-c/issues/351) and [packed-library loading](https://github.com/pizlonator/fil-c/issues/352). A minimal tail-call/forwarding reproducer also crashes unmodified stock Ruby 4.0.7 and 4.0.9 builds.

Historical Ruby 4.0.7 full-suite results, before the workspace was recovered and upgraded to 4.0.9:

| Build | Bootstrap | test-all, including leak tests | Specs |
|---|---|---|---|
| Clean released-toolchain image | 2,044 passed | 33,352 tests; 32 failures, 17 errors | 33,763 examples; 1 failure, 10 errors |

Known gaps remained when work stopped:

- Memory pressure and OOM kills during the full suites.
- GC APIs and events.
- Signal and crash reporting.
- OpenSSL secure allocation and export auditing.
- Continuations.
- Moving compaction.
- M:N scheduling.
- JIT.
- Clustered Puma.
- Rails.
- A full amd64 verdict.

## Repository guide

| Location | Contents |
|---|---|
| [`port/goal-feasibility.md`](port/goal-feasibility.md) | Final analysis and the reason for closing |
| [`port/`](port/README.md) | Candidate patches, build and validation runners, measurements and investigation history ([`STATUS.md`](port/STATUS.md)) |
| [`example/`](example/) | Docker build, application example and smoke checks |
| [`probes/`](probes/README.md) | Standalone regression tests, reproducers and pressure measurements |
| [`RECOVERY.md`](RECOVERY.md) | Provenance of the workspace recovery after the original temporary workspace was lost |
| [`licenses/`](licenses/) | Upstream licensing terms |

## Reproducing

The Docker example should still build the default port:

```fish
mise trust
mise install
test -f .env; or cp .env.example .env
mise run build
mise run test
docker run --rm -it ruby-filc:4.0.9
```

The ARM64 build and runtime system checks passed. The amd64 Dockerfile path was never verified; amd64 results came from host builds described in [`port/puma-memory.md`](port/puma-memory.md). Native libraries and extensions must be compiled with the matching Fil-C toolchain. To recreate a patched source worktree, run `python3 port/prepare-source.py` (Python 3.12+, Git). Many scripts under `port/` assume the original container layout. [`port/STATUS.md`](port/STATUS.md) records those assumptions.

No further maintenance is planned. The release-freshness lints (`mise run lint`) will start failing as new Ruby and Fil-C versions ship. Their failure doesn't mean anything regressed.

## License

Ruby modifications retain Ruby's licensing terms; see [licenses/Ruby-COPYING](licenses/Ruby-COPYING) and [licenses/Ruby-BSDL](licenses/Ruby-BSDL). Fil-C and other dependencies retain their own upstream licenses.
