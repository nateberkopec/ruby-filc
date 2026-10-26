# Port tools and investigation records

For the normal Docker build, start with [example/README.md](../example/README.md). This directory also retains the narrower tools used during development; not every script is a standalone entrypoint.

## Source preparation

- `prepare-source.py`: verify and unpack Ruby 4.0.7, initialize a local source repository, and apply the consolidated patch. `--candidate` also applies the reviewed VM-stack patch. Refuses to overwrite an existing directory.
- `export-current.py`: export the local source diff against its pristine tag into both tracked consolidated patch copies. Generated VM/parser files are excluded. Running this on an experimental branch changes what the Docker example builds.
- `sources.txt`: source paths in the consolidated patch.
- `vm-stack-clear-revised.patch`: the reviewed, incremental VM-stack candidate. The earlier `vm-stack-clear-candidate.patch` is retained only as evidence of the rejected first version.

## Build and validation runners

| Script | Scope |
|---|---|
| `validate-clean-image.sh` | Bootstrap, test-all including leak tests, and specs for a named build image |
| `check-runtime-image.sh` | Runtime integration and fresh native-gem probes |
| `check-app-image.sh` | HTTP application and default IRB checks |
| `audit-runtime.rb` | libc/interpreter/library audit |
| `build-stock-control.sh` | Unmodified Ruby 4.0.7 miniruby with GCC, from a verified archive |
| `check-vm-stack-retirement.sh` | Nine retirement scenarios with per-case exit statuses |
| `validate-vm-stack-miniruby.sh`, `validate-vm-stack-full.sh` | Candidate checks in the dedicated development builds |
| `build-current-port-toolchain.sh`, `build-current-toolchain-dependencies.sh`, `finish-current-toolchain-ruby.sh` | Historical source-built compiler/dependency/Ruby workflow |
| `profile-process-memory.py`, `summarize-process-memory.py` | Process/cgroup measurements and summaries |

Most Linux runners expect this repository mounted at `/work`, an appropriate compiler under `/compiler`, and build-path records in `/work/ta`. Do not point a runner at a different compiler or installation merely because the printed version matches. The old stopped containers still reference the lost temporary workspace; the recovered development container is separate.

`run-legacy-ruby.sh` targets the older development installation. It is not the latest-toolchain entrypoint.

## Notes and artifacts

- [STATUS.md](STATUS.md): pre-recovery history and remaining compatibility gaps.
- [vm-stack-retirement.md](vm-stack-retirement.md): retention proof, fixes, review and validation boundaries.
- `independent-review-*.md`: bounded source reviews; an OK verdict is not full-port acceptance. Probe references have been updated to the organized layout.
- [dependencies/README.md](dependencies/README.md): native dependency provenance and the OpenSSL audit.
- [native-gems/README.md](native-gems/README.md): nio4r patch and Puma probe coverage.
- `build-*`, `reproduce-*`, `compare-*`, and the remaining helpers: targeted investigation steps, with their assumptions recorded in the history.

Raw logs, compiler archives and build directories are deliberately excluded from the public repository. Old log references are historical unless a fresh check is explicitly identified.
