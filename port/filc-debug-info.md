# Fil-C debug-information footprint experiment

The 5% Puma goal is still unmet. This experiment changes Ruby's C compilation from `-ggdb3` to `-g0`, keeping `-O3`, the existing hardening flags, Fil-C instrumentation, JIT settings, coroutine implementation and packed relocations. It does not change Ruby source or remove safety checks. It remains outside the default Docker build. The new builds and measurements here are amd64; they do not establish ARM64 results.

## Why compiler debug information matters here

Unlike ordinary unmapped DWARF, Fil-C's diagnostic origins also become resident runtime metadata. In an isolated compilation of the same `string.c`, changing only the debug flag reduces `.data.rel.ro` from 566,648 to 114,880 bytes. The compiled access-check failure reference remains present. This is a configuration experiment, not stripping sections from an existing binary.

A fresh Ruby build from the verified archive and consolidated patch produces these shared-library sections:

| Section | Default `-ggdb3`, bytes | Candidate `-g0`, bytes |
|---|---:|---:|
| `.text` | 28,662,723 | 26,615,091 |
| `.data.rel.ro` | 14,834,816 | 3,477,392 |
| `.relr.dyn` | 227,704 | 47,432 |

The diagnostic trade-off is explicit: a native safety panic still names the function and rejects the access, but the newly compiled code reports `<somewhere>` instead of a C source file/line. Ruby-level backtrace behavior is tested separately. Native dependencies left unchanged retain their own diagnostic locations. No loader checks, bounds checks, use-after-free checks, read-only protections or call-argument checks are disabled.

## Validation

`check-filc-debug-flags.sh` compiles the same standalone program with each flag. Both builds pass valid reads/writes and an indirect call. Each rejects all four invalid cases with a Fil-C safety error and exit 133: an out-of-bounds write, a read after free, a read-only write and an indirect call missing a required argument. This is focused negative-control coverage, not proof of every possible memory-safety case.

The fresh `-g0` Ruby build passes:

- All 2,044 bootstrap tests.
- Array/Hash/String/Class/Object/Variable/Ractor selection: 1,375 tests, 46,299 assertions, zero failures/errors, 24 skips.
- Backtrace/exception selection: 126 tests, 4,591 assertions, zero failures/errors/skips.
- The existing nio4r and Puma native-gem probes, using the unchanged matching native gems.

A full Ruby-suite, independent checked-build and sustained-Puma verdict for this configuration are not claimed. The compiled Ruby prefix points at the existing matching Fil-C installation for its unchanged Ruby libraries and native gems; the build script never installs into that prefix. The Puma comparison changes only the loaded Ruby library, not the control installation or native dependencies.

## Heap and collector diagnostics

`filc-heap-snapshot.rb` loads the libraries selected with Ruby's `-r` flags, explicitly collects/scavenges, and records a native heap graph, process status, mappings and GC statistics. These are **intrusive diagnostics, not acceptance measurements**. The graph does not describe every allocation or static object, and logical heap sizes must not be substituted for RSS.

After loading Puma, three full/immediate collections and synchronous scavenging, separate processes report:

| Diagnostic configuration | Process RSS, KiB | `libruby` mapping RSS, KiB |
|---|---:|---:|
| Default baseline | 135,724 | 35,964 |
| Existing shape-table chunk candidate | 124,248 | 36,048 |
| Debug-information candidate | 124,912 | 24,196 |

The `libruby` read-only relocation-data mapping falls from 14,304 to 3,208 KiB RSS with `-g0`. Shape chunking instead reduces anonymous RSS. These are distinct mechanisms and are not yet a combined result. The debug-information snapshot still has roughly 14.5 MiB of `libcrypto` and 11.3 MiB of Fil-C libc mapping RSS, in addition to Ruby's library and heap.

A separate alternating non-HTTP order diagnostic tests `FUGC_CORES=8,4,2,1,1,2,4,8`. Every run checks 10,000 iterations and allocates 3,630,015 Ruby objects. Throughput ranges from 1,665.5 to 1,769.7 iterations/s, with maximum RSS 155,520-158,484 KiB. There is no clear speed or memory benefit from reducing collector workers, so no worker-count override is adopted. These timings are not HTTP acceptance evidence.

The existing shape-table patch also received fresh amd64 validation: all 2,044 bootstrap tests, 177 Class/Object/Variable/Ractor tests with 14,373 assertions and no failures/errors/skips, plus the chunk-boundary/enumeration system probe. Source commit `7c6dcb5` matches the already tracked patch exactly. This does not promote that candidate or substitute for full compatibility.

## Matched Puma comparison

Four sequential runs use the same container, 4 GiB/no swap, server CPUs 0-3 and client CPUs 4-7. Each checks 70,000 responses, including 60,000 measured requests in 30 rounds with one-second idle intervals. Builds are stopped throughout measurement. No collector setting override, application-requested GC or scavenging is used during measured rounds.

| Metric | Stock | Fil-C baseline | Shape chunks only | `-g0` only |
|---|---:|---:|---:|---:|
| Median RSS, KiB | 38,024 | 190,614 | 167,752 | 177,924 |
| Sampled peak RSS, KiB | 40,184 | 197,152 | 175,000 | 184,984 |
| Requests/s | 3,508.9 | 782.7 | 757.6 | 791.5 |
| HTTP p50, ms | 1.187 | 5.857 | 6.171 | 5.802 |
| HTTP p95, ms | 2.424 | 11.401 | 11.603 | 11.235 |
| HTTP p99, ms | 3.380 | 14.795 | 14.129 | 14.706 |

The `-g0` candidate reduces median RSS by 6.7% and peak RSS by 6.2% relative to Fil-C baseline in this comparison. Its 1.1% throughput increase is small and not established as a repeatable speedup. Its recorded GC count is almost unchanged: 1,434 versus 1,435. It still fails every acceptance ratio at **4.679x stock median RSS, 22.6% of stock throughput and 4.888x stock p50 latency**.

Shape chunking reduces RSS more, but throughput drops 3.2% and p50 latency rises 5.4% versus Fil-C baseline in this run. Its recorded GC count rises to 2,557. This supports investigating the collection-frequency cost of the smaller live-heap accounting; it does not justify compensating for a performance regression with memory savings. Neither candidate is promoted.

Stock fails the warmed-RSS-growth screen (+18.8%); the two candidates pass (-0.1% for shape chunks, +0.4% for `-g0`). Maximum client CPU utilization remains below 27% in all runs. Every response and shutdown succeeds. The measurement driver exits zero; all three stock-relative comparators exit nonzero for failed gates. These finite results do not establish leak freedom or sustained reliability, and a combined candidate has not been measured.

## Reproduction and artifacts

With the matching toolchain at `/opt/fil`, native build prerequisites available, and verified source/control installations:

```sh
bash port/build-nodebug-candidate.sh tmp/ruby-4.0.9.tar.xz tmp/ruby-nodebug \
  tmp/install-stock/bin/ruby tmp/install-filc
bash port/check-filc-debug-flags.sh ta/debug-flag-safety
mkdir -p tmp/cache-heap-extension
cp probes/c/cache-heap/* tmp/cache-heap-extension/
(cd tmp/cache-heap-extension && /path/to/filc-ruby extconf.rb && make)
/path/to/filc-ruby -I tmp/cache-heap-extension -r puma \
  probes/ruby/filc-heap-snapshot.rb ta/filc-puma-heap
```

Build/output directories for the first two commands must not already exist. Keep stock and Fil-C installations separate. For a library override, provide both `libruby.so` and `libruby.so.4.0` soname links to `libruby.so.4.0.9`, and confirm the measurement receipt records the intended library hash. Do not propagate that override to the stock bootstrap interpreter.

Consolidated source-patch SHA-256: `eb30bc400a3f80240713848dd5c3ab149e1ef7b57f7c339d96de853e4d9ee08e`.

Candidate library SHA-256: `644ec1ed02a8aa3ce656de5c0f7dfd83233a3ecc02bb195bc64e3b31c13819ec`. Shape-only library SHA-256: `cf4163fdaee5fa330413ce6dd87508a30887af6781b7d653f8f30913ea75c2ff`.

Local receipts: `ta/string-nodebug-*`, `ta/filcc-g0-driver.log`, `ta/ruby-nodebug-*`, `ta/debug-flag-safety*`, `ta/filc-puma-*-heap.*`, `ta/fugc-cores-order-diagnostic.log`, and `ta/shape-table-amd64-*`. Matched HTTP receipts and comparison logs are in `ta/puma-ruby-layout/`, with driver status in `ta/puma-ruby-layout-driver.status`.
