# Port tools and investigation records

For the normal Docker build, start with [example/README.md](../example/README.md). This directory also retains the narrower tools used during development; not every script is a standalone entrypoint.

## Source preparation

- `prepare-source.py`: verify and unpack Ruby 4.0.9, initialize a local source repository, and apply the consolidated patch. `--candidate` also applies the reviewed VM-stack patch. Refuses to overwrite an existing directory.
- `export-current.py`: export a committed local source revision against its pristine tag into both tracked consolidated patch copies; `--ref` selects the revision. Generated VM/parser files are excluded. Running this on an experimental branch changes what the Docker example builds.
- `sources.txt`: source paths in the consolidated patch. The current export comes from `filc-ruby-4.0.9-gc-dependency` (`3ae27cb`), which adds the Fil-C collector's missing incremental-build dependency to the accepted cache-only source branch; it does not promote the shape-table or registry candidates.
- `shape-cache-chunks-ruby-4.0.9.patch`: isolated Fil-C ancestor-cache allocation improvement, also included in the consolidated patch. It does not include the separate VM-stack/forwarding candidates.
- `shape-table-chunks-ruby-4.0.9.patch`: incremental Fil-C shape-table candidate on top of the current consolidated patch. Preserves capacity and stable IDs/addresses; not yet part of the default image. Validation and the still-failing memory gate are recorded in [puma-memory.md](puma-memory.md).
- `object-registry-weak-map-ruby-4.0.9.patch`: tested native weak-map registry candidate, still outside the default export. It preserves weak ObjectSpace iteration and GC-disable roots, but its throughput/latency regression makes it ineligible for promotion.
- `array-clear-ruby-4.0.9.patch`: isolated fix for references retained after `Array#clear`, including stale pointer capabilities. Tested with the memory candidates; independent default-build validation remains pending. Not in the default export.
- `vm-stack-clear-ruby-4.0.9.patch`: the incremental VM-stack candidate rebased onto Ruby 4.0.9; fresh validation remains required. `vm-stack-clear-revised.patch` is the reviewed 4.0.7 version. `vm-stack-clear-candidate.patch` records the rejected first version.

## Build and validation runners

| Script | Scope |
|---|---|
| `validate-clean-image.sh` | Bootstrap, test-all including leak tests, and specs for a named build image |
| `check-runtime-image.sh` | Runtime integration and fresh native-gem probes |
| `check-app-image.sh` | HTTP application and default IRB checks |
| `audit-runtime.rb` | libc/interpreter/library audit |
| `build-release.sh`, `test-release.sh` | Current clean Docker build and runtime system checks, exposed through mise |
| `check-latest-version.py` | Separate Ruby/Fil-C stable-release checks against the active Dockerfile pins |
| `build-stock-control.sh` | Unmodified miniruby with GCC, using the active Dockerfile version/checksum |
| `check-vm-stack-retirement.sh` | Nine retirement scenarios with per-case exit statuses |
| `validate-vm-stack-miniruby.sh`, `validate-vm-stack-full.sh` | Candidate checks in the dedicated development builds |
| `build-current-port-toolchain.sh`, `build-current-toolchain-dependencies.sh`, `finish-current-toolchain-ruby.sh` | Historical source-built compiler/dependency/Ruby workflow |
| `profile-process-memory.py`, `summarize-process-memory.py` | Process/cgroup measurements and summaries |
| `build-stock-runtime.sh` | Verified, unmodified shared Ruby with GCC for the Puma control |
| `benchmark-puma-memory.sh`, `measure-puma-memory.py`, `compare-puma-memory.py` | Checked Puma workload, CPU-isolated process clients, RSS/latency gates at 105% and throughput at 95% of stock |

Most Linux runners expect this repository mounted at `/work`, an appropriate compiler under `/compiler`, and build-path records in `/work/ta`. Do not point a runner at a different compiler or installation merely because the printed version matches. The old stopped containers still reference the lost temporary workspace; the recovered development container is separate.

`run-legacy-ruby.sh` targets the older development installation. It is not the latest-toolchain entrypoint.

## Notes and artifacts

- [ruby-4.0.9-upgrade.md](ruby-4.0.9-upgrade.md): source/toolchain identities, fresh checks and remaining failures.
- [puma-memory.md](puma-memory.md): memory/performance targets, reproducible workload, candidate trade-offs and remaining gaps.
- [upstream-filc-mmap-gc.md](upstream-filc-mmap-gc.md): FUGC reservation-accounting proposal and malloc/free reproducer, posted as [#351](https://github.com/pizlonator/fil-c/issues/351).
- [upstream-filc-relr.md](upstream-filc-relr.md): packed-relocation loader bug report and toolchain proposal, posted as [#352](https://github.com/pizlonator/fil-c/issues/352).

- [STATUS.md](STATUS.md): pre-recovery history and remaining compatibility gaps.
- [release-4.0.7-history.md](release-4.0.7-history.md): prior image results, retained without relabeling them as 4.0.9 validation.
- [vm-stack-retirement.md](vm-stack-retirement.md): retention proof, fixes, review and validation boundaries.
- `independent-review-*.md`: bounded source reviews; an OK verdict is not full-port acceptance. Probe references have been updated to the organized layout.
- [dependencies/README.md](dependencies/README.md): native dependency provenance and the OpenSSL audit.
- [native-gems/README.md](native-gems/README.md): nio4r patch and Puma probe coverage.
- `build-*`, `reproduce-*`, `compare-*`, and the remaining helpers: targeted investigation steps, with their assumptions recorded in the history.

Raw logs, compiler archives and build directories are deliberately excluded from the public repository. Old log references are historical unless a fresh check is explicitly identified.
