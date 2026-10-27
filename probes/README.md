# Runtime probes

These are standalone system-level programs, not a single all-green test suite. Some verify fixed regressions, some reproduce unresolved failures, and others only print measurements. They keep their original lifetime assertions, collection counts and workload sizes.

## Ruby

Run from the repository root, using the Ruby build being investigated. For example:

```fish
docker run --rm --memory=8g --memory-swap=8g \
  --mount type=bind,src=(pwd),dst=/work,readonly \
  ruby-filc:4.0.9 ruby /work/probes/ruby/callcache-cme-lifetime.rb dispatch
```

| Files under `ruby/` | Purpose |
|---|---|
| `callcache-*`, `protected-callcache.rb` | Weak class/method-entry caches, active-call lifetime and callback invalidation |
| `metaclass-publication.rb`, `subclasses-concurrent-gc.rb` | Concurrent class construction and enumeration |
| `vm-stack-*` | Retired VM-stack storage; requires the separate candidate for its expected lifetime results |
| `tail-forward-minimal.rb` | Known failure when tailcalling into an argument-forwarding method; `plain` is the non-tail control |
| `review-*`, `gc-*`, `finalizer-churn.rb` | Collection state, retention, accounting and finalizer behavior |
| `buffer-*` | Mapping/resizing behavior; private-file growth remains an unresolved failure |
| `ractor-port-pressure.rb`, `ractor-port-phases.rb`, `ractor-select.rb` | Ractor behavior and memory pressure; port pressure has exceeded the 8 GiB limit |
| `allocation-pressure.rb`, `class-retention*.rb`, `struct-retention.rb`, `weakmap-gc-phases.rb` | Allocation/lifetime measurements, not broad correctness verdicts |
| `nio4r.rb`, `puma.rb` | Native-gem probes; first build matching native extensions as described in `port/native-gems/README.md` |
| `puma-memory-app.rb` | Order-processing HTTP app driven and measured by `port/benchmark-puma-memory.sh`; the 5% RSS target is still unmet |
| `shape-cache-chunks.rb` | Cache chunk boundaries, ivar lookup/copy/removal, GC and concurrent Ractor construction |
| `fiddle.rb`, `ioctl.rb`, `timezone.rb`, `scheduler-stress.rb` | Focused runtime integration checks |

The release-image regression runner is `example/regressions.sh`. The candidate retirement matrix is `port/check-vm-stack-retirement.sh`, which accepts a Ruby executable and an output prefix. Runners under `port/` may assume the development container's `/work` and `/compiler` layout.

## C

`c/` contains small compiler/runtime reproductions and native heap-dump helpers:

- `setjmp-*`: allocation pressure, parallel calls, OOM and scavenging.
- `mremap-support.c`: supported mapping operations.
- `binding/`: dynamic-loader symbol binding.
- `cache-heap/`, `vm-stack-heap/`: native heap/root inspection helpers using matching Ruby internal headers.
- `timezone.c`: timezone integration.

Compile with the same Fil-C compiler/runtime as the Ruby being investigated. GCC controls must use ordinary system libraries instead. Do not load a helper built against another Fil-C ABI into Ruby.

Historical results are in `port/STATUS.md`; new local logs belong in the ignored `ta/` directory. A script finishing is not evidence that each recorded test or subprocess passed.
