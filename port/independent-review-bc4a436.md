# Independent correctness review — Ruby 4.0.7 Fil-C port at `bc4a436`

## Review basis

- Repository: `/tmp/ruby-filc/ruby-4.0.7-glibc`
- Baseline: `6bfdb48`
- Reviewed HEAD: `bc4a436b267e80ab83c89e5ebfdce6df0496718e`
- Export reviewed: `/tmp/ruby-filc/ruby-4.0.7-filc.patch`
- Status and known gaps: `/tmp/ruby-filc/port/STATUS.md`
- Runtime reference: `/tmp/ruby-filc/source/libpas`
- API reference: `/tmp/ruby-filc/filc-0.686-linux-aarch64/pizfix/stdfil-include/stdfil.h`

The generated modifications in `gc.rbinc`, `miniprelude.c`, `revision.h`, and `vm.inc` were ignored as requested. The worktree also contains pre-existing build artifacts; no source files were modified during this review.

## Findings

### P1 — An explicit collection exposes and then overwrites concurrent `GC.enable` state

**Files:** `gc/filc/filc.c:164-173`, `gc/filc/filc.c:179-197`, `gc/filc/filc.c:306-316`, `gc.c:4517-4521`

**Status:** Proven with a runtime reproduction.

When GC is logically disabled, `rb_gc_impl_start` implements the required “`GC.start` remains potent” behavior by changing the same `registry.disabled` flag used by the public `GC.enable`/`GC.disable` API:

```c
bool disabled = !rb_gc_impl_gc_enabled_p(objspace);
if (disabled) registry_set_disabled(&objspace->registry, false);
zgc_request_and_wait();
if (disabled) registry_set_disabled(&objspace->registry, true);
```

The temporary internal enable is therefore visible to another Ractor. More importantly, the unconditional restore at line 172 overwrites a concurrent public `GC.enable`.

Reproduction on the reviewed Fil-C worktree:

```ruby
a = Array.new(500_000) { Object.new }
GC.disable

r = Ractor.new do
  Ractor.receive
  sleep 0.01
  GC.enable
end

r << true
GC.start
p [r.value, GC.enable]
```

Command used:

```sh
docker exec ruby-filc-glibc sh -lc \
  'cd /work/ruby-4.0.7-glibc &&
   timeout 20 ./miniruby --disable-gems -e \
   '\''a=Array.new(500000){Object.new}; GC.disable;
      r=Ractor.new { Ractor.receive; sleep 0.01; GC.enable };
      r << true; GC.start; p [r.value, GC.enable]'\'''
```

Fil-C result:

```text
[false, true]
```

This proves both failures:

1. The worker's `GC.enable` reports `false`, because it observes the adapter's temporary internal enable rather than the logical disabled state.
2. The subsequent main-Ractor `GC.enable` reports `true`, proving `GC.start` restored disabled state and discarded the worker's enable request.

An architecture-matched stock Ruby control produced:

```text
[true, false]
```

`GC.start` is documented to work while GC is disabled, but it must not expose a temporary logical state change or undo a later `GC.enable`.

**Impact:** Applications using Ractors can successfully call `GC.enable` yet remain with GC disabled. Since this port implements disable by strongly retaining every registered Ruby object, the lost enable can cause unbounded object retention and severe memory growth. The API return values are also incorrect during the race.

**Smallest safe correction:** Separate the user-visible logical disable state from the internal “release retained roots for this explicit collection” state. `rb_gc_impl_gc_enabled_p` and public enable/disable operations must consult and update the logical state. After the explicit collection, retained roots should be restored only if the logical state is still disabled. A generation/version check can prevent overwriting a concurrent transition, but a separate logical flag is also needed so the concurrent `GC.enable` returns the correct previous state.

---

### P2 — Automatic Fil-C cycles increment `GC.count` while `GC.disable` is in force

**Files:** `gc/filc/filc.c:736-740`, `gc/filc/filc.c:306-316`, `gc.rb:66-77`

**Status:** Proven with a runtime reproduction and stock comparison.

The adapter retains every Ruby object when disabled, but it returns the raw process-wide Fil-C cycle number for `GC.count`:

```c
size_t
rb_gc_impl_gc_count(void *objspace_ptr)
{
    return (size_t)zgc_completed_cycle();
}
```

Fil-C must continue collecting its underlying C heap, but those implementation cycles should not be exposed as Ruby garbage collections while the public API says garbage collection is disabled.

Reproduction:

```ruby
GC.start
GC.disable
before = GC.count

objects = []
300_000.times { objects << "x" * 64 }
sleep 0.2

p [before, GC.count]
```

Reviewed Fil-C result:

```text
[5, 6]
```

The same workload on the container's stock Ruby produced:

```text
[1, 1]
```

There is no explicit `GC.start` after `GC.disable`; the count increase is an automatic runtime cycle. This contradicts the documented `GC.disable` behavior and makes monitoring, allocation tests, and code that detects unexpected collections report collections that Ruby explicitly disabled.

**Smallest safe correction:** Maintain a Ruby-visible collection count rather than directly exposing `zgc_completed_cycle()`. Automatic runtime cycles completed while the logical Ruby GC state is disabled should be excluded, while an explicit `GC.start` invoked during disable should still count. This should share the corrected logical-state bookkeeping from the P1 fix.

---

### P2 — `ObjectSpace::WeakMap` under-reports per-entry memory after adding Fil-C weak handles

**File:** `weakmap.c:39-45`, `weakmap.c:187-197`

**Status:** Proven from structure layout and a runtime probe.

Under Fil-C, each `weakmap_entry` grew from two fields to four:

```c
struct weakmap_entry {
    VALUE key;
    VALUE val;
#ifdef __FILC__
    zweak *key_ref;
    zweak *val_ref;
#endif
};
```

However, `wmap_memsize` still accounts for only two `VALUE` fields per entry:

```c
size += st_table_size(w->table) * (2 * sizeof(VALUE));
```

This omits `key_ref` and `val_ref`, or at least two pointer widths per live entry. The corresponding `WeakKeyMap` implementation correctly uses `sizeof(struct wkmap_key)` at `weakmap.c:814-824`.

Runtime probe with 100 entries:

```ruby
require "objspace"

wm  = ObjectSpace::WeakMap.new
wkm = ObjectSpace::WeakKeyMap.new
keys = Array.new(100) { Object.new }
vals = Array.new(100) { Object.new }

keys.each_with_index do |key, index|
  wm[key] = vals[index]
  wkm[key] = vals[index]
end

p [ObjectSpace.memsize_of(wm), ObjectSpace.memsize_of(wkm), wm.size]
```

Result:

```text
[5064, 5064, 100]
```

The equal result is impossible for the port's owned entry storage: both maps have equivalent wrapper/table counts, but a Fil-C `weakmap_entry` has four pointer-sized fields while `wkmap_key` has two. On this 64-bit target, the WeakMap result omits at least 1,600 bytes for 100 entries, apart from any separately allocated runtime weak-handle overhead.

**Impact:** `ObjectSpace.memsize_of`, memory profilers, and leak/accounting tests systematically under-report live WeakMap storage. The error scales linearly with map size.

**Smallest safe correction:** Replace the hard-coded expression with:

```c
size += st_table_size(w->table) * sizeof(struct weakmap_entry);
```

If the runtime can expose the allocation size of each `zweak`, that separately owned overhead could also be included, but accounting for the complete C entry is the minimum correction.

## Additional targeted observations

- I exercised explicit `IO::Buffer::MAPPED` resizing to zero. It raises `Errno::EINVAL` at `io_buffer.c:1801-1817` because `mremap(..., new_size = 0, ...)` is attempted before the internal-buffer zero-size case. The container's stock Ruby exhibits the same behavior, and pristine source uses the same native `mremap` path, so I did **not** attribute this as a new Fil-C-port finding.
- I inspected the private-growth fallback, shared remapping path, runtime `mremap` implementation, registry compaction/trimming, finalizer queues, dispatch-storage reuse, weak maps, weak concurrent sets, object-ID weak storage, and the GC-disable retention mechanism. I did not find another sufficiently proven port-introduced defect within the bounded review.
- The documented private file-backed growth association loss and broader profiler/page/generation/event, signal, compaction, callcc, JIT, and memory-pressure gaps were not re-reported as findings.

## Validation and coverage limitations

Performed:

- Established the baseline and reviewed commit sequence with Git status, log, diff statistics, and per-commit diffs.
- Checked the exported patch and relevant surrounding source.
- Inspected the full Fil-C GC adapter and focused changes in `weakmap.c`, `concurrent_set.c`, `io_buffer.c`, GC integration, atomic EC handling, finalization, dispatch reuse, and runtime weak/finalizer/remapping implementations.
- Ran only isolated, read-only runtime probes in `ruby-filc-glibc`.
- Used stock Ruby controls for the two observable GC-state behaviors.
- `git diff --check 6bfdb48..bc4a436` reported no whitespace errors.

Not performed:

- No compilation or mutation of shared container state.
- No heavy bootstrap, spec, or `test-all` reruns.
- No exhaustive semantic audit of all 141 patched files.
- No amd64 or alternative-toolchain validation.
- The review was intentionally bounded; capability-tagging changes outside the focused paths and shutdown-only native-finalizer reentrancy received only partial inspection.

## Merge verdict

**Merge verdict: BLOCK**

The concurrent `GC.enable` overwrite is a reachable global-state correctness defect with potentially severe retention consequences. The `GC.count` and WeakMap accounting defects should be corrected alongside it.