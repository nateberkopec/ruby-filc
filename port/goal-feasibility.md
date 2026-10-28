# Feasibility of the Puma goal with the released Fil-C compiler

`GOAL.md` asks for Puma on Fil-C Ruby 4.0.9 within 5% of stock Ruby for RSS, throughput and p50/p95/p99 latency, with Fil-C safety checks preserved. This note measures where the remaining gap comes from. **With the released optfil 0.687 compiler and runtime, the gap is dominated by code that Fil-C itself generates for every pointer access, function frame and allocation, and by the size of that code. It is not concentrated in Ruby-port inefficiencies that source changes can remove.** No measurement here disables a check, forces collection or changes the stock baseline.

## CPU cost per request

The latest matched receipts (`ta/puma-combined/`, 30 warmup and 30 measured rounds of 2,000 checked requests, server CPUs 0-3, client CPUs 4-7) give:

| Run | Requests/s | Server CPU per request | Server cores in use |
|---|---:|---:|---:|
| 1 stock | 3,302.9 | 0.296 ms | 0.98 |
| 6 stock | 3,303.7 | 0.296 ms | 0.98 |
| 3 combined Fil-C | 799.7 | 1.802 ms | 1.44 |
| 4 combined Fil-C | 821.9 | 1.765 ms | 1.45 |

Fil-C spends about **6.0x stock's CPU time per request**. It already uses 1.45 cores because FUGC marks and sweeps concurrently, so additional idle cores cannot hide the cost: request execution is GVL-serialized, as on stock.

A `perf record` sample of the combined candidate under the same load (`ta/interpreter-overhead/puma-filc-perf-summary.txt`) attributes 30% of samples to threads named `ruby` (FUGC collector threads and the idle main thread) and 70% to Puma threads. By library, 46% is in `libpizlo.so` (collector, allocator, checked atomic pointer loads, auxiliary-capability allocation, weak-cell reads, checked memory copies) and 37% in `libruby`. No Ruby function exceeds about 10% of samples. The cost is spread across the whole interpreter.

## Instruction counts for core interpreter kernels

`port/measure-interpreter-overhead.sh` runs fixed kernels from `probes/ruby/interpreter-overhead.rb` under `perf stat`, subtracting each runtime's startup. Counts include every thread, so collector work is counted. Combined-candidate result (`ta/interpreter-overhead/combined.txt`):

| Kernel | Stock instructions | Fil-C instructions | Ratio | Cycle ratio |
|---|---:|---:|---:|---:|
| startup only | 210M | 1,769M | 8.41 | 8.04 |
| `while` loop, 10M iterations | 1,260M | 16,996M | 13.49 | 11.40 |
| `fib(27)` | 172M | 2,699M | 15.67 | 15.41 |
| Struct attribute update | 618M | 8,964M | 14.50 | 18.35 |
| small Array allocation | 829M | 7,704M | 9.29 | 11.44 |
| String interpolation | 946M | 7,943M | 8.39 | 8.57 |
| Hash lookup | 1,352M | 10,929M | 8.08 | 9.19 |

The `while` kernel allocates nothing and calls no methods, yet executes 13.5x as many instructions: about 1,700 machine instructions per iteration of seven VM instructions, versus 126 for stock.

## Where those instructions go

`putobject_INT2FIX_1_` is a representative VM instruction: in C it advances `cfp->pc` and pushes one fixnum. Compiled by Fil-C (inspected in the call-threaded experiment below, where each instruction is a separate function), it performs a stack-limit check and frame link/unlink for the GC's root scan; null, alignment, lower-bound and upper-bound checks on the control frame; a load of the auxiliary capability for the `pc` field and a marking-state test for the store barrier; the same sequence again for `sp`; and a separate store clearing the auxiliary capability of the pushed stack slot, because `VALUE` must be a pointer type to carry capabilities. That is about 100 fast-path instructions for what stock compiles into a handful.

The direct-threaded build has a second cost. Fil-C lowers computed `goto` into one shared `switch`, so every instruction returns to a single dispatch block. Thirty address-taken locals of `vm_exec_core` are allocated lazily and become loop-carried values there, and Fil-C re-stores the capability of each into the GC-visible frame on every dispatch (`ta/interpreter-overhead/vm-exec-core-dispatch.s`). In the `while` profile, that block takes 41% of samples, and the 30 re-stores alone take 26% (`ta/interpreter-overhead/while-vm-exec-core-hot-offsets.txt`). `vm_exec_core` is about 14% of Puma-thread samples, so removing the re-stores entirely would be worth at most a few percent of Puma CPU.

Two experiments, both built from the combined candidate tree, are not promoted:

- **Call-threaded dispatch** (`OPT_THREADED_CODE=2`) removes the shared phi block but adds a checked Fil-C call per instruction. `while` took 5.18 s versus 4.07-4.97 s for the combined build on the same host, and `fib(30)` took 1.43 s versus 1.17-1.23 s. No improvement.
- **Dropping `-fstack-protector-strong`**, which duplicates protection Fil-C already provides and is not a Fil-C check, reduced the kernel suite's total instructions by only 0.6% (218.6G to 217.2G).

## Memory floor from code size

End-of-load smaps from the same receipts show file-backed mappings alone exceeding stock's whole-process RSS:

| Mapping | Stock RSS, KiB | Combined Fil-C RSS, KiB |
|---|---:|---:|
| Anonymous and heap | 32,724 | 74,424 |
| `libruby` | 4,668 | 24,192 |
| libc | 1,556 | 11,628 |
| libcrypto + libssl | 4,100 | 12,132 |
| Fil-C runtime (`libpizlo`, `libyolo*`) | none | 3,892 |
| **Total** | **44,972** | **132,512** |

The Fil-C `libruby` `.text` is 26.6 MB, versus 4.0 MB for stock, and Fil-C libc's text is 12.5 MB, versus 2.0 MB for glibc. Most of this is the inline checking and capability code described above. Both runtimes' libraries are almost entirely resident. With zero heap overhead, the libraries' resident code would still exceed the 47,221 KiB acceptance limit derived from this stock run (105% of 44,972 KiB). Anonymous memory also carries Fil-C's per-object headers, an auxiliary capability word for each pointer-bearing word, and concurrent-collector headroom.

## Conclusion and options

Meeting `GOAL.md` requires about a 6x reduction in Fil-C CPU per request and more than a 2.8x reduction in RSS, without removing checks. Source-level port work has delivered gains of a few percent to about 20% each: shape-cache chunks, packed relocations, `-g0`, retirement, registry compaction and packed OpenSSL. The largest remaining source-level opportunity identified here, the dispatch re-store, is bounded at a few percent of Puma CPU. Closing the gap would require new Fil-C compiler and runtime capabilities, such as much cheaper or eliminated checks on proven-safe accesses, a smaller generated-code footprint, or a different capability representation. The investigation boundary in `STATUS.md` says to stop and discuss before pursuing that kind of upstream dependency.

## Reproduction

```sh
bash port/measure-interpreter-overhead.sh tmp/install-stock/bin/ruby tmp/install-filc/bin/ruby tmp/puma-combined-candidate
```

Run this as a user with access to user-space hardware counters. The receipts above came from a Debian 13 container on the amd64 host, with `/usr` mounted read-only, the matching optfil 0.687 toolchain mounted at `/opt/fil`, 4 GiB of memory and no swap. Other unrelated workloads were running on the host during this session, so the wall-clock microbenchmark timings above vary by up to about 20% between repetitions. Instruction counts are much more stable and are the primary evidence.
