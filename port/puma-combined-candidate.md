# OpenSSL layout and a combined Puma candidate

This is an experimental amd64 configuration, not a promoted default or a claim that `GOAL.md` is achieved. It brings previously isolated reclamation and performance candidates together, and tests a smaller OpenSSL mapping layout without removing TLS functionality or safety checks.

## OpenSSL: packing helps; `-g0` does not

The released optfil 0.687 compiler reports commit `36f07a2f8f8141b3488d7ca20a680fd629886eeb`. Its OpenSSL is 3.6.5, configured for `linux-x86_64`, `-O3`, assembly through the existing checked Fil-C bridges, dynamic zlib support, `/etc/ssl`, and the `/opt/fil` engine/provider directories.

`build-openssl-layout.sh` verifies and extracts the matching archive, then applies the exact `projects/openssl.projeny` from that compiler commit. It preserves those features and builds with `-Wall -O3 -g0`. The C wrappers, explicit safety checks, constant-time port changes and assembly are unchanged. It never installs into `/opt/fil`.

Unlike Ruby's original `-ggdb3` build, this OpenSSL was already built without detailed compiler-origin debug information. The `-g0` experiment does **not** materially reduce its sections:

| libcrypto section | Released, bytes | Rebuilt `-g0`, bytes | Same objects, packed relocations |
|---|---:|---:|---:|
| `.text` | 20,011,852 | 20,012,220 | 20,012,220 |
| `.data.rel.ro` | 4,255,616 | 4,255,616 | 4,255,616 |
| `.rela.dyn` | 4,420,032 | 4,420,032 | 144 |
| `.relr.dyn` | absent | absent | 70,088 |

The useful change is relinking the same objects with `-Wl,-z,pack-relative-relocs`. Both libcrypto and libssl acquire a real `GLIBC_ABI_DT_RELR` requirement and load normally. The loader check is not disabled or bypassed. OpenSSL already references versioned libc symbols; the earlier tiny-library loader failure still reproduces when no libc version requirement is recorded. Merely adding `--undefined=GLIBC_ABI_DT_RELR` to that tiny example did not fix it, and is not used here. Packing is not being enabled indiscriminately for all native extensions.

## Dependency and TLS validation

The build restores all eight upstream recipes removed by the Fil-C descriptor, restores the skipped QUIC radix recipe, and applies the existing bioprint test-argument correction. The full run remains **nonzero: 356 recipe files, 4,574 tests, six failing recipes**:

- Symbol presence expects ordinary exports rather than the Fil-C namespace.
- Four secure-allocation recipes encounter the port's explicit `Cannot do secure malloc in Fil-C` rejection. All four direct binaries reproduce the rejection on both installed and rebuilt libraries.
- AF_ALG encounters `unsupported syscall: 206` (`io_setup`) on both installed and rebuilt libraries in this amd64 environment. The earlier successful AF_ALG result for another toolchain/architecture is not substituted for this result.

A separate export audit finds all 5,905 libcrypto and 608 libssl defined dynamic exports unchanged across installed/plain/packed variants (type, binding, visibility, name and version). This does not make the upstream ordinary-namespace audit pass.

These failures are retained, not excluded or converted into success. `build-openssl-layout.sh` therefore exits nonzero after producing the build artifacts and running the full suite. The omitted shlib-loading, corrected bioprint and unskipped QUIC-radix recipes pass in this run.

Installed, rebuilt-unpacked and rebuilt-packed libraries each pass **592 Ruby/OpenSSL tests, 5,598 assertions, zero failures/errors, three skips**. Each also passes the local Puma TLS probe. `probes/ruby/puma.rb --tls` creates an in-memory test certificate, verifies trusted HTTPS responses, rejects both an untrusted certificate and the wrong hostname, and checks 100 POSTs across five concurrent keep-alive clients with forced GC. No private key is written to the repository. The default plain-HTTP probe remains available.

`check-openssl-layout-safety.sh` runs the same native AES probe against all three library variants. Each passes an AES-128 known-answer/decrypt control and rejects all six invalid cases with `filc safety error`, exit 133: undersized key/input/output, invalid rounds, key/output overlap and writing to read-only output. This is focused evidence that the existing checked assembly bridges remain active, not proof of every cryptographic or memory-safety case.

## Combined Ruby configuration

The combined library uses `-g0`, the original hardening/optimization settings, disabled JITs and ucontext. Its seven source overlays are:

1. `checked-size-arithmetic-ruby-4.0.9.patch`
2. `cpu-feature-init-ruby-4.0.9.patch`
3. `object-registry-vector-ruby-4.0.9.patch`
4. `array-shrink-ruby-4.0.9.patch`
5. `hash-retirement-ruby-4.0.9.patch`
6. `shape-table-chunks-ruby-4.0.9.patch`
7. `short-string-equality-ruby-4.0.9.patch`

It does not stack the superseded array-clear patch or the alternative weak-map registry patch. Applying the consolidated export and these overlays to a separate verified release extraction produces byte-identical results for all **144 modified source files** in the compiled tree. Separate library and standard-extension copies are frozen before measurements; installed controls remain unchanged.

The combined configuration passes:

- **2,044 bootstrap tests**.
- **1,797 selected Array/Hash/Set/String/Class/Object/Variable/Ractor/Backtrace/Exception/JSON/C-table tests, 64,668 assertions, zero failures/errors, 27 skips**.
- **592 Ruby/OpenSSL tests, 5,598 assertions, zero failures/errors, three skips**, using packed OpenSSL.
- All **188 array/table reclamation cases**, **25 deleting-callback cases**, **105,375 string-comparison checks**, and **21,404 arithmetic checks**.
- CPU-startup, shape/cache-chunk, weak-enumerator lifetime, three registry-retention rounds, GC accounting, all six concurrent/fork scenarios, nio4r epoll/poll/select, and plain/TLS Puma probes.

The normal integration is tested here. Previous independent checked builds covered component combinations, not this complete bundle; no complete-bundle checked-build or full Ruby-suite verdict is claimed. Known broader GC compatibility failures remain outstanding.

## Measurement isolation and warmup

The measurement driver now accepts `--server-library-path` and `--server-rubylib`. Overrides are applied only to Ruby's subprocess environment, not to Python or its load-client processes. Otherwise the Fil-C libcrypto/libssl files could be selected by native Python or command-line utilities with incompatible ABIs. The receipt records the actual server overrides and hashes both loaded OpenSSL libraries as well as libruby. The paired shell wrapper also converts inherited dependency paths into Fil-C-only server options and does not forward explicit candidate options to stock. Three environment/wrapper regressions were added; all **11 measurement/comparison tests pass**. Workload logic, CPU allocation and numeric gates are unchanged.

The six runs use stock, the prior arithmetic/CPU/`-g0` control, combined, combined, control, stock. Every runtime gets **30 warmup batches and 30 measured batches of 2,000 checked requests**: 120,000 total, 60,000 measured. The longer warmup exercises the same workload on every configuration; it does not force collection, manipulate the stock heap, or change acceptance thresholds. Earlier five-warmup receipts are not comparable to this series. Resources remain 4 GiB/no swap, server CPUs 0-3 and client CPUs 4-7, with no concurrent builds or collector overrides during load.

Measured results (RSS in KiB, latency in ms):

| Run | Median RSS | Peak RSS | Requests/s | p50 | p95 | p99 | GC count |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 stock | 42,720 | 45,700 | 3,302.9 | 1.220 | 2.952 | 3.884 | 2,104 |
| 2 control | 176,260 | 184,056 | 793.5 | 5.784 | 11.217 | 14.625 | 2,403 |
| 3 combined | 143,042 | 149,876 | 799.7 | 5.809 | 11.021 | 13.762 | 3,935 |
| 4 combined | 142,122 | 150,168 | 821.9 | 5.653 | 10.745 | 13.400 | 3,938 |
| 5 control | 177,300 | 184,220 | 810.9 | 5.647 | 10.983 | 14.472 | 2,401 |
| 6 stock | 42,208 | 45,092 | 3,303.7 | 1.208 | 2.934 | 4.189 | 2,085 |

The combined mean median RSS is **19.3% lower** and mean peak **18.5% lower** than this series' Fil-C control. Mean throughput is about **1.1% higher**, but two runs do not establish a small performance gain; median latency is slightly worse in both paired comparisons. GC counts are about 64% higher. Component effects cannot be attributed independently from this bundle comparison.

**Every stock-relative numeric gate fails.** The combined runs use 3.348/3.367x stock median RSS and 3.280/3.330x peak, deliver 24.2/24.9% of stock throughput, and have 4.764/4.678x median latency. Both combined growth screens pass (-1.2%/-1.3%), but both stock screens still fail (+10.6%/+14.5%) despite the longer warmup. Thus the stock stability concern is unresolved, not cured by increasing warmup. Client CPU maxima remain below 27%. All six runs complete 120,000 checked responses and clean shutdowns; finite completion is not general leak-freedom evidence.

End-of-load smaps, captured before diagnostic `/gc`, show libcrypto/libssl RSS falling from **14,560/2,436 KiB** in the control to **10,692/1,440 KiB** in both combined runs. The combined libruby uses **24,192 KiB** and Fil-C libc **11,628 KiB**. Anonymous residency varies with collection timing; these individual snapshots are not substitutes for the sampled acceptance medians/peaks. Loaded-library hashes confirm the intended frozen Ruby and OpenSSL copies in both candidate runs.

Full compatibility, sustained reliability, general resource reclamation and every numerical requirement remain required before promotion or goal completion. Default exports and installed controls remain unchanged.

## Reproduction and provenance

```sh
bash port/build-openssl-layout.sh tmp/openssl-3.6.5.tar.gz \
  tmp/openssl-0.687.projeny tmp/openssl-layout-new
bash port/check-openssl-layout-safety.sh ta/openssl-safety-new \
  /opt/fil/lib tmp/openssl-layout-new/artifacts/plain tmp/openssl-layout-new/artifacts/relr
```

Use new output directories. The first command's full native suite has the failures described above; inspect its status/log instead of treating compiled artifacts as a passing suite. The descriptor is retrieved from `https://raw.githubusercontent.com/pizlonator/fil-c/36f07a2f8f8141b3488d7ca20a680fd629886eeb/projects/openssl.projeny`; its Git blob was checked against the commit-specific GitHub API result (`6abffdfe3469bc7cc36debcbcff7f82e9879ea98`). The matching archive is available at `https://deb.debian.org/debian/pool/main/o/openssl/openssl_3.6.5.orig.tar.gz`.

Build the Ruby configuration with `build-nodebug-candidate.sh`, its four normal arguments, and the seven patch paths listed above. Do not install over a control prefix. Use the server-only driver options to select its library/standard extensions and the packed OpenSSL directory; keep the Python process environment free of Fil-C dependency overrides.

SHA-256 identities:

- OpenSSL archive: `a2157c2830efdec3788939b00c9b0638306d3f0bbb76dc4832ee503bb397df98`.
- Fil-C descriptor: `828192c156d7673ac1edecbb98a6991a1c7b2c244e40bf5717f3576a9742c732`.
- Installed libcrypto/libssl: `5cda239c2f45325853f1e4ec68057ef457b8969d367d3fd2abc9d1fc7560c1c4` / `fa380a68c2edce2fc7ce76eff44e497b667c89c844eeb07ad00488cfc2dfccf2`.
- Combined libruby: `44c8ed241ce19d7361687983e5acf24050ccda9973a936284d1b5a2d2ed43db9`.
- Packed libcrypto/libssl: `cf62cc8333041fb98ecb685d1ab01824ea04b570bf565275c18d74eb8c74259f` / `1895d4942b51dd4250848d3c6e8417f1382491fe937d23df96e66d529448cbf7`.

Local evidence: `ta/openssl-baseline-identity.log`, `ta/openssl-layout-*`, `ta/openssl-safety-*`, `ta/relr-explicit-abi-marker.*`, `ta/puma-combined-*`, and `ta/puma-combined/`. Full-suite library hashes match the frozen packed artifacts. An initial OpenSSL build used static rather than dynamic zlib support; it was stopped and replaced by a fresh matching build before measurement. The combined validation driver completed every runtime check, then failed its final host `sha256sum` because of an inherited Fil-C dependency override. Hashing was rerun with a clean host environment, and the launcher was corrected; the original aggregate exit 127 is retained rather than relabeled as a passing runtime-driver status. The first direct allocator-rejection loop similarly stopped when host `grep` inherited the Fil-C library path. The corrected child-only override run (`ta/openssl-layout-rejections-final/`) verifies all eight expected rejections across both library variants.
