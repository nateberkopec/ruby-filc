# Ruby 4.0.7 built with Fil-C

Historical record from outer commit `a186fd7`, before the Ruby 4.0.9 / Fil-C 0.687 upgrade. Commands and results below describe that earlier checkout, not the active Dockerfile. Use [the current build guide](../example/README.md) for the active version.

An experimental Docker base image built from Ruby 4.0.7 plus the local Fil-C port. It uses Fil-C 0.686 and glibc, not a musl Ruby runtime. Known compatibility failures remain; this is not a drop-in replacement for the official Ruby image.

The original workspace was recovered after its temporary directory disappeared. The build inputs below retain their original hashes. Validation results on this page are historical unless identified as fresh recovery checks; most original raw logs are no longer available. See [RECOVERY.md](../RECOVERY.md).

## Build and run

From this directory:

```fish
docker build -t ruby-filc:4.0.7 .
docker run --rm ruby-filc:4.0.7 ruby -v
docker run --rm -it ruby-filc:4.0.7
```

The compiler archive must be present in `dist/`; downloads are excluded from Git. The recovered local workspace has the ARM64 archive. For a fresh checkout or another architecture, obtain the matching archive from the [Fil-C 0.686 release](https://github.com/pizlonator/fil-c/releases/tag/v0.686):

| Docker architecture | Archive in `dist/` |
|---|---|
| arm64 | `optfil-0.686-linux-aarch64.tar.xz` |
| amd64 | `optfil-0.686-linux-x86_64.tar.xz` |

The Dockerfile verifies the compiler archive, libyaml, and Ruby release checksums. It downloads pristine Ruby 4.0.7 and applies `ruby-4.0.7-filc.patch`, exported through port commit `78e4bb7`. It does not copy a previously built Ruby. Changing the Ruby version requires a matching source patch and checksum, not just a different build argument. The current local base image is also tagged `ruby-filc:4.0.7-78e4bb7`; the application image has been rebuilt and checked against it.

Only the ARM64 build has been tested. `BUILD_JOBS` defaults to four. The runtime image is about 2.04 GB uncompressed and retains the compiler and build tools.

## Adapt an application Dockerfile

Build the base image above, then change the application base:

```diff
-FROM ruby:4.0-slim
+FROM ruby-filc:4.0.7
```

For an application with a Gemfile, Gemfile.lock, and app.rb:

```dockerfile
FROM ruby-filc:4.0.7
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
CMD ["bundle", "exec", "ruby", "app.rb"]
```

Use the Fil-C base for both the gem-building stage and runtime stage of a multi-stage application. Do not copy native gems from an ordinary Ruby image. Native extensions must be compiled with Fil-C; extensions that assume an integer `VALUE` can require source changes.

A Rack/WEBrick application is included:

```fish
docker build -f Dockerfile.app -t ruby-filc-app:4.0.7 .
docker run --rm -p 127.0.0.1:9292:9292 ruby-filc-app:4.0.7
```

Request `http://localhost:9292/` once the server starts. Its JSON response reports Ruby 4.0.7 and `/opt/fil/bin/filcc`.

Puma 8.0.2 also builds and serves requests on this image, but nio4r 2.7.5 needs two integer/VALUE fixes. The patch, source package, and results are documented in [native-gems/README.md](../port/native-gems/README.md). They are not automatically applied by `bundle install`. A full Rails application has not been validated.

## Runtime configuration

Ruby uses a modular FUGC adapter and ucontext fibers. YJIT and ZJIT are disabled. Fil-C libraries are installed in `/opt/fil`; Ruby is installed in `/usr/local`.

The image supplies Fil-C-built OpenSSL, zlib, libffi, and libyaml. `CC`, `CXX`, and pkg-config point at the Fil-C toolchain. It includes `tzdata`, the Fil-C zoneinfo link, and `netbase` for service/protocol names. The default locale is `C.UTF-8`.

Ubuntu packages still use the ordinary system toolchain and ABI. Installing a system `libfoo-dev` package does not make that library usable by a Fil-C extension. Build native dependencies with Fil-C and use fresh gem/Bundler caches.

The image has no `docker-entrypoint.sh`. Its default command is `irb`, and it is not size-optimized. Nothing has been published to a registry.

## Validation

Run the image smoke checks:

```fish
docker run --rm --mount type=bind,src=(pwd),dst=/checks,readonly ruby-filc:4.0.7 bash /checks/smoke.sh
```

Run the cache-lifetime, reentrant TracePoint/warning, protected-dispatch, heap-dump and concurrent class-construction regression checks:

```fish
docker run --rm --memory=8g --memory-swap=8g --mount type=bind,src=(pwd),dst=/checks,readonly ruby-filc:4.0.7 bash /checks/regressions.sh
```

Verified on Linux ARM64 through OrbStack:

- Clean-source image build, Ruby version/compiler selection, UTF-8 locale, and named service lookup.
- Allocation/GC, suspended/resumed fibers, Fiddle calls, JSON, YAML, zlib, OpenSSL, Bundler, and HTTPS certificate verification.
- Building/loading a native extension and detecting an intentional out-of-bounds native write with a Fil-C safety error.
- Rebuilt Rack/WEBrick application returns HTTP 200 with Ruby 4.0.7 and the Fil-C compiler; the default IRB command evaluates `1 + 1` to `2`.
- Freshly compiled patched nio4r and unmodified Puma serve 100 POSTs across five concurrent keep-alive clients, with a forced collection in every request.

Current clean build-stage validation, as an unprivileged user:

| Suite | Result for `78e4bb7` |
|---|---|
| `make btest` | 2,044 tests passed |
| `make test-all`, including normally excluded leak tests | 33,352 tests; 32 failures, 17 errors, 243 skips |
| `make test-spec` | 33,763 examples; 1 failure, 10 errors |

Current-image smoke, libc audit, expanded cache/concurrency regressions, GC-state, WeakMap accounting, mapped-buffer and fresh native-gem probes passed. The full suites contain no Fil-C safety errors, but test-all has three leaked-descriptor warnings. This clean sequence recorded no OOM kill; the preceding worktree run of the same changes had a Ractor-port SIGKILL and one new OOM kill. These variable outcomes do not establish production suitability.

The method-entry fix makes idle normal call caches weak while retaining the selected entry through active calls, including TracePoint and Warning.warn callbacks that remove or replace the method. Independent follow-up review found no issues in the five-file change. Normal and VM-check bootstrap each pass 2,044 tests; the packaged regression checks cover lifetime, redefinition, alias/removal, accessor events, keyword setup and tailcall behavior.

The image includes the reviewed fix for a concurrent metaclass-construction trap found in `e68cce3` and reproduced on `74beca5`. It uses Ruby's VM barrier while the metaclass hierarchy is incomplete. The reproduction passed five worktree runs; focused class/module/refinement/Ractor tests passed 392 cases. A separate VM-check build passed both concurrency probes and all 2,044 bootstrap tests. The barrier's multi-Ractor performance cost is not yet benchmarked.

Compared with the `70c5604` image, iclass memory growth failed again, while Rational GCD, Ripper warn-callback memory growth and the Ractor-port SIGKILL were absent. These are previously observed, variable failure identities, not evidence of general memory reclamation. The earlier serial leak selection still had 7 failures in 67 tests. No assertions were weakened or failing cases suppressed.

These images use the released optfil toolchain. A separate coherent source-built toolchain now builds the full runtime and matching native dependencies, and passes bootstrap, optional C-API specs, standalone regressions, HTTPS and fresh nio4r/Puma probes. It still has 34 test-all failures, 17 errors and an OOM kill in the full run, despite lower peak RSS in an isolated Ractor comparison. Auditing OpenSSL's omitted tests also found remaining dependency gaps. This experimental toolchain is not used by this Dockerfile; see `../port/STATUS.md`.

The runtime audit checked 2,059 ELF files, their interpreters, installed packages, libc archives, and loaded Ruby libraries. It identifies glibc 2.44 and no musl packages, libc archives, or loaded libraries. Two libc++ portability headers named `musl.h` remain in the compiler distribution; they are not a musl runtime. The audit script is [audit-runtime.rb](../port/audit-runtime.rb).

## Remaining limitations

GC profiling/events and several other GC APIs are incomplete. Signal/crash-reporting behavior differs. Shared mapped-buffer resizing now preserves cross-fork visibility using supported remapping APIs, but private file-backed growth still loses file association. Continuations, moving compaction, M:N scheduling, and JIT support are unfinished.

Memory-growth failures remain. The named-Struct assertion failed in earlier runs; its longer churn probe shows bounded class counts but a much larger footprint than stock Ruby. Other leak assertions still fail in the latest complete runs. A fork-under-GC-stress timeout also occurred once and remains unexplained despite later passing runs.

Ractor-heavy workloads can exceed the memory limit. A standalone C `_setjmp` workload also exhausts 8 GiB on Fil-C 0.686, so this is not solely a Ruby-object retention problem. The reproduction is attached to [upstream issue #335](https://github.com/pizlonator/fil-c/issues/335#issuecomment-6357134997). A separate coherent source-built compiler/runtime now completes four controlled runs with 8 GiB RAM and no swap, but post-collection RSS still reaches roughly 6.4 GiB. Ruby bootstrap and three Ractor probes also pass on that toolchain. It is not included in this image and has not received full extension/application validation.

See [the port status](../port/STATUS.md) for exact logs, other outstanding work, and the upstream reporting boundary. Do not treat the passing application probes as evidence of production readiness or full Rails compatibility.
