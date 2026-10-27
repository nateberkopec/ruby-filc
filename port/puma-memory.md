# Puma memory acceptance

The requested target is **not met**: Ruby 4.0.9 / Fil-C 0.687 must run the same Puma application at no more than 105% of stock Ruby's memory use, without sustained memory growth. The benchmark deliberately exits nonzero when this target fails. Passing HTTP checks alone is not memory acceptance.

## Workload and measurement

`probes/ruby/puma-memory-app.rb` serves a small order-processing application with Puma 8.0.2 and nio4r 2.7.5. Each POST parses JSON containing 50 line items and a note, calculates totals and a SHA-256 digest, and returns JSON. Five concurrent keep-alive clients check every response, including its unique request ID, items, total and digest. Puma runs one process with five threads; both JITs are disabled.

`measure-puma-memory.py` runs the HTTP client outside the measured Ruby process. It samples that process's Linux `smaps_rollup` every 100 ms, recording RSS, PSS, USS and swap. The primary acceptance metrics are median and peak RSS during the measured load/idle rounds. RSS includes native code, allocator metadata and thread stacks, not just Ruby heap objects. Client memory and file cache outside the Ruby process are not included.

The default warmup is five batches of 1,000 requests. Ten measured batches follow, with two seconds idle between batches. No application-requested collection occurs during those rounds. One full GC after measurement is diagnostic only and is excluded from the acceptance metrics. Increasing `--rounds` and `--requests` extends the soak without changing the application.

The comparison also screens for growth: the median idle RSS in the last three rounds minus the median in the first three must not exceed 5% of the measured median. This is conservative: allocator warmup can fail it even on stock Ruby. A failure is not by itself proof of a leak, and a pass cannot prove leak freedom beyond the tested workload and duration.

Results include interpreter/shared-library hashes, CPU affinity, relevant GC environment settings, server versions, raw samples, server output and final mappings. Both server shutdown and every HTTP response must succeed. Missing samples, sampler errors and workload failures are not converted into successful measurements.

## Run in a prepared Linux container

The two runtimes must have their own native gems compiled with their respective compilers. Do not reuse Fil-C extension binaries in stock Ruby. Both sides in this investigation use the same nio4r source patch; see [native-gems/README.md](native-gems/README.md).

`build-stock-runtime.sh` builds an unmodified, shared stock Ruby from the archive/version/checksum pinned by `example/Dockerfile`. It disables both JITs, selects ucontext, clears Fil-C compiler/library settings and installs into a new prefix. Its prerequisites are GCC/G++, make, a bootstrap Ruby, autoconf, bison and native development packages for OpenSSL, libyaml, zlib, libffi, readline, gdbm and GMP. The investigation built this control in the same Ubuntu container as the Fil-C runtime; it uses the system loader, not the Fil-C loader.

For example, inside a container with this repository mounted at `/work`, the verified Ruby archive already available, and those dependencies installed:

```sh
bash /work/port/build-stock-runtime.sh /work/tmp/ruby-4.0.9.tar.xz /opt/ruby-stock
env -u GEM_HOME -u GEM_PATH -u BUNDLE_APP_CONFIG /opt/ruby-stock/bin/gem install --local --no-document \
  /work/port/native-gems/nio4r-2.7.5-filc.gem /work/native-gems/cache/puma-8.0.2.gem
gem install --local --no-document \
  /work/port/native-gems/nio4r-2.7.5-filc.gem /work/native-gems/cache/puma-8.0.2.gem
bash /work/port/benchmark-puma-memory.sh /opt/ruby-stock/bin/ruby /usr/local/bin/ruby \
  /work/ta/puma-memory-comparison --rounds 30 --requests 2000 --idle 1
```

Python 3 is required. Run the container with a fixed CPU set and memory/swap limits. These measurements used Linux ARM64, CPUs 0-3, 4 GiB RAM and no additional swap. The driver clears Fil-C gem and library overrides for stock Ruby, preserves the Fil-C environment for the other run, and records separate measurement/comparison exit statuses. The ignored gem/archive files above are local build inputs, not files provided by a fresh clone; the native-gem notes explain their preparation.

## Investigation

The first 3,500-request comparison used the existing stock `ruby:4.0.9` image and the released Fil-C image. Median RSS was 33,012 versus 682,954 KiB, and peak RSS was 34,304 versus 831,708 KiB. This established the failure but was not the final matched-container control.

The existing VM-stack and forwarding candidates were then built into the full runtime. The VM-stack lifetime reproducer changed from 99 retained strings to zero, confirming the intended library was loaded. It did not remove the large Puma footprint. An initial library-override attempt omitted the soname symlink and still loaded the baseline; those receipts are labeled `before-soname` and are not candidate evidence.

Stop-the-world FUGC did not materially improve the footprint. `FUGC_THRESHOLD_MULTIPLIER=1.01` reduced the short-run median to 270,308 KiB, still far above stock. Neither setting was adopted as a default or used to represent normal memory acceptance.

A native heap snapshot identified a 402,653,184-byte allocation rooted by `rb_shape_tree`: Ruby's ancestor lookup cache reserves its entire maximum capacity up front. Another allocation is the 20 MiB shape list. These are sparse virtual reservations on stock Ruby; Fil-C's collector accounts for the cache reservation as live memory, increasing its automatic-collection threshold. This is not evidence of 384 MiB of resident cache entries or a request-object leak.

The isolated `shape-cache-chunks-ruby-4.0.9.patch`, now included in the consolidated export, replaces only the Fil-C ancestor-cache reservation with lazily allocated 4,096-node chunks. Nodes retain stable addresses and IDs, and the existing maximum capacity, balancing algorithm and VM lock remain unchanged. Native/stock builds retain the original contiguous representation. No application GC calls, reduced cache limit or relaxed memory threshold are introduced.

With the same development runtime before and after this one-file change, an 11,000-request run changed median RSS from 759,248 to 311,728 KiB (59% lower), and peak RSS from 902,680 to 361,128 KiB (60% lower). The matched GCC control used 34,884 KiB median and 35,360 KiB peak. The modified runtime still failed the 5% target.

A longer run with 10,000 warmup requests followed by 60,000 measured requests checked all 70,000 responses on each runtime. Stock used 34,220 KiB median / 36,008 KiB peak; the chunked development runtime used 324,644 / 375,064 KiB. Fil-C's idle-growth screen was 4.3%; stock's was 6.3%, so stock did not satisfy that stability screen. Post-GC live-object counts were 30,772 and 31,674 respectively. These observations do not establish general leak freedom.

The clean exported build, without the separate VM-stack/forwarding candidates or GC tuning, also checked all 70,000 responses. It used 329,258 KiB median RSS and 386,724 KiB peak, versus the same stock control's 34,220 / 36,008 KiB: 9.62x median and 10.74x peak. Its idle-growth screen was 4.2%, post-GC RSS was 217,144 KiB, and post-GC live-object count was 31,721. The 105% comparison fails. Receipts: `ta/puma-memory-clean-long.*` and `ta/puma-memory-clean-comparison.*`.

The remaining gap is not just garbage awaiting reclamation: in the long run, the Fil-C `libruby` mappings alone occupied 53,356 KiB RSS, versus 4,472 KiB for stock `libruby`. The instrumented library by itself exceeded the entire stock process's 105% budget. Meeting that budget with this application requires further compiler/runtime footprint work, not merely clearing Ruby object references.

## Validation and delivery

The isolated change is source commit `1a83325` on `filc-ruby-4.0.9-shape-chunks`, based directly on the released port baseline. Development-branch commit `b0ad29c` applies the same change alongside the separate stack/forwarding candidates. Only the isolated change was exported into the default Docker build.

- Normal and checked development builds each pass all 2,044 bootstrap tests (139.84 and 208.08 seconds).
- The existing standalone port regressions pass. The normal class/object/variable/Ractor selection passes 177 tests and 14,390 assertions. Normal builds do not expose `RubyVM::Shape`, so those debug-only tests did not run in that selection.
- A full checked runtime runs 70 shape tests and 401 assertions: zero failures and three errors from unsupported `GC.auto_compact=`. Rebuilding the same checked runtime without the cache change produces exactly the same three errors. No added failure identities, Fil-C safety errors or descriptor warnings appear in that comparison. The changed source was restored and rebuilt afterward.
- `probes/ruby/shape-cache-chunks.rb` passes on stock, normal, checked and clean-image runtimes. It exercises more than 380,000 cache nodes, chunk boundaries, compiled ivar reads, copying, removal/reinsertion, explicit GC and four concurrent Ractors.
- A fresh build from pristine Ruby plus the consolidated patch succeeds. Clean-image smoke, libc audit, existing cache/concurrency and GC-state checks, mapped-buffer checks, freshly compiled nio4r/Puma probes and the new shape-cache probe all pass.

Clean build image: `sha256:0a12bf4430d6d4140898e72786e5c5511da282973a0ea95dd86f160f406e7069`. Runtime image: `sha256:d582697cf5293db3fa457702b5f59cf365397405e089da291a67e3fec08d34b6`. The local `ruby-filc{,-build}:4.0.9` tags include the cache change. Nothing was published. `mise run test` includes the new shape-cache system probe; the failing comparative memory gate remains a separate explicit command.

Consolidated patch SHA-256: `926e4388a264f9c9d608371ff18bf9c7d18bb8c499203455ed36f2877125cb6a`. Isolated patch SHA-256: `243646325611fb52def6d51deb970fe270610ea218c13fa9350384d41a67181c`.

Raw receipts are under the ignored `ta/` directory: `puma-memory-*`, `shape-chunks-*`, and `puma-memory-chunked-long/`. The full port remains experimental; memory improvements must not be read as full Ruby compatibility or acceptance of the separate VM-stack/forwarding candidates.
