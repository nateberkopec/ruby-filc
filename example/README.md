# Ruby 4.0.9 built with Fil-C 0.687

An experimental Docker base image using glibc, not musl. The port has been rebased onto verified Ruby 4.0.9 sources. A fresh ARM64 build and the runtime/native-extension/cache/concurrency system checks pass for this version pair. The original 4.0.9 baseline's full suites completed with failures; the complete Ruby suites have not passed on the port. See [the upgrade record](../port/ruby-4.0.9-upgrade.md) for exact artifacts and results.

## Build and run

From the repository root:

```fish
mise trust
mise install
test -f .env; or cp .env.example .env
mise run build
docker run --rm ruby-filc:4.0.9 ruby -v
docker run --rm -it ruby-filc:4.0.9
mise run test
```

`mise run build` downloads the matching optfil archive if missing, then builds both the build-stage and runtime images. Docker verifies the compiler, libyaml and Ruby checksums before using them. Archives remain in the ignored `example/dist/` directory.

The build uses pristine Ruby 4.0.9 plus `ruby-4.0.9-filc.patch`, not an existing Ruby executable. It preserves the previously accepted port changes through the historical `78e4bb7` checkpoint and Ruby 4.0.9's upstream fixes, plus the Fil-C shape-cache allocation improvement. The separate VM-stack-retirement and forwarding candidates are not included.

The interpreter and `libruby` use ELF packed relative relocations to reduce mapped relocation metadata. The flag is deliberately scoped through Ruby's `XLDFLAGS`, not general `LDFLAGS`: some Fil-C 0.687 native extensions fail to load when packed because their link omits a required glibc ABI dependency. Extension flags remain unchanged. See the [memory measurements](../port/puma-memory.md) and [unposted upstream reproducer](../port/upstream-filc-relr.md).

| Artifact | SHA-256 |
|---|---|
| Ruby 4.0.9 `.tar.xz` | `a8057adb39f51ad6dc3106237504c93dd792bb515837b4fe7817ae21ed7e51f4` |
| optfil 0.687 Linux ARM64 | `375995867dcd3e91533efba6328a5057e51cf7db5a1ffa413ad391d0336ade6e` |
| optfil 0.687 Linux amd64 | `2dc295715dc3347c1cc1b41f7a937b13a076e651e71db42f3adf00d5fb075bfe` |

Sources: [Ruby release](https://www.ruby-lang.org/en/news/2026/10/23/ruby-4-0-9-released/) and [Fil-C release](https://github.com/pizlonator/fil-c/releases/tag/v0.687). Fil-C's release tag points to `2db72c646daa1acad2754bcb0e2f220f732e9789`. This uses the latest published stable release, not unreleased main-branch changes.

`BUILD_JOBS` defaults to four. The active validation host is Linux ARM64 through OrbStack; amd64 remains unvalidated. The images retain the compiler and build tools and are not size-optimized. Nothing has been published to a container registry.

For direct Docker use, first populate `dist/` with the matching optfil archive, then run `docker build -t ruby-filc:4.0.9 .` from this directory.

## Native dependencies and applications

Ruby uses a modular FUGC adapter and ucontext fibers. YJIT and ZJIT are disabled. Matching Fil-C libraries and tools live in `/opt/fil`; Ruby lives in `/usr/local`. The image includes matching OpenSSL, zlib, libffi and a freshly compiled libyaml.

Native extensions and libraries must be compiled with the same Fil-C toolchain. Do not copy native gems from ordinary Ruby or another Fil-C build. Ubuntu's development libraries are not substitutes for Fil-C libraries. Extensions that assume an integer `VALUE` can need source changes.

For an application:

```dockerfile
FROM ruby-filc:4.0.9
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
CMD ["bundle", "exec", "ruby", "app.rb"]
```

A Rack/WEBrick example is included. From this directory:

```fish
docker build -f Dockerfile.app -t ruby-filc-app:4.0.9 .
docker run --rm -p 127.0.0.1:9292:9292 ruby-filc-app:4.0.9
```

The response at `http://localhost:9292/` reports the running Ruby version and compiler. The nio4r patch and gem preparation are documented in [port/native-gems/README.md](../port/native-gems/README.md). Fresh Puma 8.0.2/nio4r 2.7.5 builds now run the checked HTTP memory workload on Ruby 4.0.9, but the 5% memory target is not met; see [the memory comparison](../port/puma-memory.md). The nio4r patch is not automatically applied by ordinary `bundle install`.

## Checks and limitations

`mise run test` rebuilds as needed and runs the smoke and cache/concurrency regression scripts in an 8 GiB, no-extra-swap container. These cover loading dependencies, fibers and GC, HTTPS, compiling/loading a native extension, intentional native buffer-overflow detection, packed interpreter/library relocations, weak method caches, reentrant callbacks and concurrent class construction. They are not the complete Ruby suites.

Run the two version checks independently or through `mise run lint`:

```fish
mise run lint:ruby-version
mise run lint:fil-c-version
```

These compare Dockerfile pins with the latest stable upstream releases. They intentionally run without source-file caching: upstream can release a new version even when no local file changes. Stale pins fail with exit 1; failed lookups or malformed metadata fail with exit 2. Preview releases are not treated as stable. A green version check does not establish build/runtime correctness.

The prior Ruby 4.0.7 results, including test-all/spec failures, OOMs, missing APIs and the libc audit, remain in [release-4.0.7-history.md](../port/release-4.0.7-history.md). They are retained as evidence, not relabeled as Ruby 4.0.9 results. See [port/STATUS.md](../port/STATUS.md) for the broader investigation and [RECOVERY.md](../RECOVERY.md) for recovery provenance.
