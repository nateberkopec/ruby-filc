# Ruby 4.0.7 with Fil-C

An experimental Ruby 4.0.7 port to Fil-C, using glibc and Fil-C's FUGC collector. This repository contains the source patches, Docker example, regression probes, and investigation notes. **Ruby's full suites still fail. This is not a drop-in replacement for ordinary Ruby.**

## Build the Docker example

Place the matching optfil 0.686 archive from the [Fil-C release](https://github.com/pizlonator/fil-c/releases/tag/v0.686) in `example/dist/`. The Dockerfile checks its SHA-256, downloads verified pristine Ruby and libyaml sources, and builds Ruby with the port patch.

```fish
cd example
docker build -t ruby-filc:4.0.7 .
docker run --rm ruby-filc:4.0.7 ruby -v
docker run --rm -it ruby-filc:4.0.7
```

Only Linux ARM64 has been validated so far. The Dockerfile also selects an amd64 compiler archive, but that path is unverified. See [example/README.md](example/README.md) for the application example, smoke checks, native-extension requirements, and libc audit.

Native libraries and extensions must be compiled with the matching Fil-C toolchain. Ordinary system libraries and binaries built with a different Fil-C compiler/runtime are not interchangeable.

## Source development

The public repository tracks patches rather than generated Ruby build trees or compiler binaries. Recreate a local source worktree with Python 3.12+, Git, and a configured Git author identity:

```fish
python3 port/prepare-source.py
```

This verifies the Ruby archive, creates `ruby-4.0.7-glibc/` with its own local Git history, tags the pristine source, and applies the consolidated port patch. It refuses to overwrite an existing directory. The worktree is ignored by the outer repository; its source changes must be exported into the tracked patches to publish them.

The VM-stack-retirement candidate is a separate, reviewed incremental patch. Its focused tests pass, but full-suite validation was interrupted. To investigate it in a fresh worktree:

```fish
python3 port/prepare-source.py --candidate
```

After making and validating source changes, `python3 port/export-current.py` regenerates both consolidated patch copies and `port/sources.txt`. This includes the current worktree's changes; do not use it to silently promote an unvalidated candidate into the Docker example.

The older scripts under `port/` document the investigation and often assume a Linux container with this directory mounted at `/work`, a matching toolchain under `/compiler`, and path records under `ta/`. They are not all standalone setup commands. [port/STATUS.md](port/STATUS.md) records those assumptions and unresolved work.

## Current status

The Docker example uses the consolidated port through the original `78e4bb7` checkpoint. The separate newer-toolchain installation uses Fil-C source revision `9d1ed206e0ccfc1ec114471386befeba643a5f86` and the VM-stack candidate. The identical printed Fil-C version does not establish ABI compatibility between these toolchains.

Historical complete-suite results before workspace recovery:

| Build | Bootstrap | test-all, including leak tests | Specs |
|---|---|---|---|
| Clean released-toolchain image | 2,044 passed | 33,352 tests; 32 failures, 17 errors | 33,763 examples; 1 failure, 10 errors |
| Coherent newer toolchain, before VM-stack candidate | 2,044 passed | 33,367 tests; 34 failures, 17 errors; one OOM kill | 33,763 examples; 1 failure, 10 errors |

The VM-stack candidate passed 2,044 bootstrap tests and 50 standalone regressions in each of normal and checked builds before recovery. Its independent follow-up review found no concrete defects. Its full test-all/spec/C-API run did not complete.

Fresh recovery checks reproduce the exact port and candidate hashes, reconstruct an identical complete Ruby source tree, and pass all nine retirement scenarios on the recovered normal and checked binaries. A combined forwarding/tail-call probe still traps on both baseline and candidate Fil-C; the host stock Ruby 4.0.5 control also fails, with an argument error. Stock Linux 4.0.7 comparison and diagnosis remain pending. These results do not establish full compatibility.

Remaining gaps include memory pressure/OOM, GC APIs and events, signal/crash reporting, private file-backed buffer growth, OpenSSL secure allocation and export auditing, and broader native-gem/application coverage. Rails, clustered/TLS Puma, long-running workloads, and amd64 are not yet validated. Continuations, moving compaction, M:N scheduling, and JIT support are unfinished.

## Recovery and provenance

The original temporary workspace disappeared. Compiler-volume and Docker-image copies survived; retained successful file operations recovered 125 text assets. The consolidated patch and revised VM-stack patch match their recorded hashes exactly. Original local Git commit history and most raw test logs were not recovered. Old commit IDs and log paths in the investigation notes are historical identifiers, not commits in this repository or promises that those logs are present.

See [RECOVERY.md](RECOVERY.md) for verified identities and fresh checks. Raw recovery data, session logs, archives, downloaded gems, source/build trees, and compiler binaries are not committed.

Ruby modifications retain Ruby's licensing terms; see [licenses/Ruby-COPYING](licenses/Ruby-COPYING) and [licenses/Ruby-BSDL](licenses/Ruby-BSDL). Fil-C and other dependencies retain their own upstream licenses.
