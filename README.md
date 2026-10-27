# Ruby 4.0.9 with Fil-C

An experimental Ruby 4.0.9 port to Fil-C 0.687, using glibc and Fil-C's FUGC collector. This repository contains the source patches, Docker example, regression probes, and investigation notes. **The port has not passed Ruby's full suites. This is not a drop-in replacement for ordinary Ruby.**

## Repository guide

| Location | Contents |
|---|---|
| [`example/`](example/) | Reproducible Docker build, application example and smoke checks |
| [`probes/`](probes/README.md) | Standalone Ruby and C regression tests, failure reproducers and pressure measurements |
| [`port/`](port/README.md) | Source preparation/export tools, build/validation runners and investigation history |
| [`ruby-4.0.9-filc.patch`](ruby-4.0.9-filc.patch) | Consolidated patch used by the Docker build |
| [`RECOVERY.md`](RECOVERY.md) | Recovery provenance, artifact identities and remaining recovery work |
| [`licenses/`](licenses/) | Upstream licensing terms |

Start with `example/` to build Ruby. Use `probes/` to reproduce individual behaviors. Historical reviews and experiments live under `port/`; they are not the primary setup instructions.

## Build the Docker example

Use the standard mise tasks from the repository root. The build task downloads the matching optfil archive; Docker checks its SHA-256 and builds from verified pristine Ruby/libyaml sources and the port patch.

```fish
mise trust
mise install
test -f .env; or cp .env.example .env
mise run build
mise run test
docker run --rm -it ruby-filc:4.0.9
```

The clean Ruby 4.0.9 / Fil-C 0.687 ARM64 build and runtime system checks pass. Complete-suite validation is running separately; see [the upgrade record](port/ruby-4.0.9-upgrade.md). The Dockerfile also selects an amd64 compiler archive, but that path is unverified. See [example/README.md](example/README.md) for the application example, smoke checks, native-extension requirements, and libc audit.

Native libraries and extensions must be compiled with the matching Fil-C toolchain. Ordinary system libraries and binaries built with a different Fil-C compiler/runtime are not interchangeable.

## Development checks

`mise tasks` lists the entrypoints. `mise run lint:ruby-version` and `mise run lint:fil-c-version` each check the Docker build pin against the latest stable release. Both are included in `mise run lint`, along with a working-tree secret scan. The version checks are deliberately uncached and fail when release metadata cannot be verified.

`hk.pkl` uses the managed lint/test hooks. Install project-local hooks with `mise exec -- hk install --mise`. No credentials or environment keys are needed; `.env.example` is intentionally empty. The secret scanner excludes only verified public Ruby fixture/documentation paths, not all ignored files or `.env`.

## Source development

The public repository tracks patches rather than generated Ruby build trees or compiler binaries. Recreate a local source worktree with Python 3.12+, Git, and a configured Git author identity:

```fish
python3 port/prepare-source.py
```

This verifies the Ruby archive, creates `ruby-4.0.9-glibc/` with its own local Git history, tags the pristine source, and applies the consolidated port patch. It refuses to overwrite an existing directory. The worktree is ignored by the outer repository; its source changes must be exported into the tracked patches to publish them.

The VM-stack-retirement candidate remains separate. Its Ruby 4.0.7 version was reviewed and passed focused tests, but full-suite validation was interrupted. The Ruby 4.0.9 rebase is in `port/vm-stack-clear-ruby-4.0.9.patch` and needs fresh validation. To investigate it in a fresh worktree:

```fish
python3 port/prepare-source.py --candidate
```

After making and validating source changes, `python3 port/export-current.py` regenerates both consolidated patch copies and `port/sources.txt`. It exports committed `HEAD`, or a revision selected with `--ref`. Do not silently promote an unvalidated candidate into the Docker example; the current baseline is `filc-ruby-4.0.9-baseline`.

The older scripts under `port/` document the investigation and often assume a Linux container with this directory mounted at `/work`, a matching toolchain under `/compiler`, and path records under `ta/`. They are not all standalone setup commands. [port/STATUS.md](port/STATUS.md) records those assumptions and unresolved work.

## Current status

The Docker example now targets Ruby 4.0.9 with the latest stable Fil-C release, 0.687. The 142-file port applies without conflicts; upstream class-variable-cache and extension-unloading fixes are preserved. Its clean ARM64 build and runtime/cache/concurrency system checks pass. Full-suite validation is running separately. The consolidated patch still excludes the VM-stack candidate.

The older recovered development installation uses Ruby 4.0.7, Fil-C source revision `9d1ed206e0ccfc1ec114471386befeba643a5f86` and the VM-stack candidate. The identical printed Fil-C version does not establish ABI compatibility between these toolchains.

Historical Ruby 4.0.7 complete-suite results before workspace recovery:

| Build | Bootstrap | test-all, including leak tests | Specs |
|---|---|---|---|
| Clean released-toolchain image | 2,044 passed | 33,352 tests; 32 failures, 17 errors | 33,763 examples; 1 failure, 10 errors |
| Coherent newer toolchain, before VM-stack candidate | 2,044 passed | 33,367 tests; 34 failures, 17 errors; one OOM kill | 33,763 examples; 1 failure, 10 errors |

The VM-stack candidate passed 2,044 bootstrap tests and 50 standalone regressions in each of normal and checked builds before recovery. Its independent follow-up review found no concrete defects. Its full test-all/spec/C-API run did not complete.

Fresh recovery checks reproduce the exact port and candidate hashes, reconstruct an identical complete Ruby source tree, and pass all nine retirement scenarios on the recovered normal and checked binaries. A combined forwarding/tail-call probe still traps on both baseline and candidate Fil-C; the host stock Ruby 4.0.5 control also fails, with an argument error. A fresh, unmodified stock Linux Ruby 4.0.7 build also segfaults on the minimal tail-call reproducer, while its ordinary-call control returns 42. Fresh stock 4.0.9 and Fil-C 0.687 controls reproduce the same failure, with exits 139 and 133 respectively; their ordinary-call controls both return 42. A fix remains pending. These results do not establish full compatibility.

Remaining gaps include memory pressure/OOM, GC APIs and events, signal/crash reporting, private file-backed buffer growth, OpenSSL secure allocation and export auditing, and broader native-gem/application coverage. Rails, clustered/TLS Puma, long-running workloads, and amd64 are not yet validated. Continuations, moving compaction, M:N scheduling, and JIT support are unfinished.

## Recovery and provenance

The original temporary workspace disappeared. Compiler-volume and Docker-image copies survived; retained successful file operations recovered 125 text assets. The recovered Ruby 4.0.7 consolidated patch and revised VM-stack patch matched their recorded hashes exactly. Those original exports remain in Git history; the current Ruby 4.0.9 exports have new identities. Original local Git commit history and most raw test logs were not recovered. Old commit IDs and log paths in the investigation notes are historical identifiers, not commits in this repository or promises that those logs are present.

See [RECOVERY.md](RECOVERY.md) for verified identities and fresh checks. Raw recovery data, session logs, archives, downloaded gems, source/build trees, and compiler binaries are not committed.

Ruby modifications retain Ruby's licensing terms; see [licenses/Ruby-COPYING](licenses/Ruby-COPYING) and [licenses/Ruby-BSDL](licenses/Ruby-BSDL). Fil-C and other dependencies retain their own upstream licenses.
