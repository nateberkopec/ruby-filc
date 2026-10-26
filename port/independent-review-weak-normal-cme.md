# Independent review: weak normal-call-cache CME lifetime

**Baseline:** `70c560472a3f5fe0e669c5bff70e9ae368968480`  
**Authoritative change:** `/tmp/ruby-filc/port/weak-normal-cme.patch`  
**Reviewed source delta:** `vm_callinfo.h`, `vm_insnhelper.c` (`+24/-4`)

## Findings

### P1 — A reentrant C-call hook can invalidate and collect the weak CME while the current attr/struct dispatch still needs it

**Locations:** `vm_callinfo.h:361-362`, `vm_callinfo.h:473-489`, `vm_insnhelper.c:4083-4104`, `vm_insnhelper.c:4795-4829`, `vm_insnhelper.c:4848-4854`, `vm_insnhelper.c:4903-4970`, `vm_eval.c:204-240`, `vm_eval.c:284-306`

Normal heap call caches now hold the CME only through `zweak`:

```c
if (cme && type == cc_type_normal) {
    cme_ref = (const struct rb_callable_method_entry_struct *)zweak_new((void *)cme);
}
```

Ordinary dispatch is safe while the cache remains valid: the live receiver class owns its CC table, whose `ccs->cme` or associated callable table keeps the resolved CME alive. That invariant stops holding if Ruby code invalidates the method during the current dispatch.

Attribute and optimized Struct methods emit a synthetic `RUBY_EVENT_C_CALL` before executing the operation. `VM_CALL_METHOD_ATTR` repeatedly resolves the CME from the cache, but does not retain one strong resolved CME across the event hook:

```c
EXEC_EVENT_HOOK(... vm_cc_cme(cc)->def->original_id, ... vm_cc_cme(cc)->owner ...);
var = func;
EXEC_EVENT_HOOK(... vm_cc_cme(cc)->def->original_id, ... vm_cc_cme(cc)->owner ...);
```

A TracePoint hook can execute arbitrary Ruby, including removing or redefining the method and forcing GC. For a leaf class, invalidation calls `rb_vm_ccs_invalidate_and_free`, which sets the cache class to `Qundef` and removes the class-side ownership before the hook returns (`vm_method.c:373-395`, `vm_method.c:475-497`). An attr pseudo-method has no method frame holding its CME. The `cme` local in `vm_call_method_each_type` is last used to select the switch arm at `vm_insnhelper.c:4912`, so it is not a guaranteed Fil-C root across the hook.

After collection:

- `vm_call_attrset_direct`, `vm_call_ivar`, or the Struct helpers resolve and dereference the weak CME again; and
- the C-return hook resolves it once more.

That can produce a null dereference/Fil-C safety trap. With `VM_CHECK_MODE`, `vm_cc_cme` can instead fail its class-validity assertion because invalidation has already written `Qundef`.

This also contradicts the existing lifetime contract in `imemo.c:340-349`, which explicitly says an invalidated normal CC's CME must not be accessed.

A focused regression should cover removal during the active attr call:

```ruby
klass = Class.new { attr_writer :x }
obj = klass.new
armed = true

trace = TracePoint.new(:c_call) do |event|
  if armed && event.self.equal?(obj) && event.method_id == :x=
    armed = false
    klass.class_eval { remove_method :x= }
    GC.start(full_mark: true, immediate_sweep: true)
  end
end

trace.enable { obj.x = 1 }
raise unless obj.instance_variable_get(:@x) == 1
```

The same lifetime pattern should be tested for attr readers and Struct accessors.

**Smallest fix:** resolve the CME once before invoking the C-call hook and keep that resolved pointer strongly live through the operation and C-return hook. Pass that resolved CME to the attr/Struct helpers and use it for event metadata rather than calling `vm_cc_cme(cc)` after reentrant Ruby execution. The equivalent `vm_call0_body` paths must use the same protected resolved CME.

## Other audited areas

- `vm_cc_new` correctly makes only Fil-C normal heap CMEs weak. Super and refinement caches remain direct, and `VM_CC_ON_STACK`/`VM_CALLCACHE_UNMARKABLE` caches remain direct.
- The constructor’s `RB_GC_GUARD(cme_value)` protects the source CME while the weak reference and cache are initialized.
- Both heap-to-stack representation transitions now resolve `cme_` before making the copy unmarkable:
  - attr cache copy at `vm_insnhelper.c:4942-4955`;
  - protected-call copy at `vm_insnhelper.c:5075-5080`.
- The direct `cme_` mutation in `vm_eval.c:263-275` is restricted to the unmarkable stack-cache branch and therefore does not write a direct CME into a normal heap cache.
- The Fil-C root-cache validity path retains its resolved class through the CME validity read with `RB_GC_GUARD(klass)`.
- Remaining direct `cc->cme_` reads in `imemo.c` are in the non-Fil-C branch. `BOX_CC` is currently only an unused macro definition.
- The non-Fil-C constructor/getter behavior remains direct and otherwise unchanged.

## Validation and limitations

Existing candidate evidence is broad but does not cover invalidation from inside the active synthetic C-call event:

- normal and checked bootstrap: 2044 tests each;
- focused 788-test run: only the three known ObjectSpace gaps;
- C-API: 1577 examples, no failures or errors;
- full specs: 33763 examples with the known Signal and `GC::Profiler` failures;
- Ractor invalidation stress passes, but mutations happen between completed calls rather than from a hook during an in-flight attr/Struct dispatch;
- basic TracePoint attr coverage does not remove/redefine the method inside `:c_call`.

No new build or runtime reproduction was performed, per the task constraints. There is still no completed full `test-all` or clean-image candidate result.

**Merge verdict: BLOCK**