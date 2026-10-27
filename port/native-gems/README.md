# Native gems on Ruby 4.0.7 / Fil-C

These artifacts are local experiments, not published gems.

The older development installation, through port commit `e267785`, is at `/opt/ruby-filc` inside `ruby-filc-glibc`. Its gem directory is `/work/native-gems`; set `GEM_HOME` to that path when running those probes. Ruby's configured compiler is `/opt/fil/bin/filcc`. Current-image validation is separate and described below.

## nio4r 2.7.5

`nio4r-2.7.5.patch` removes two assignments of integer event flags to a Ruby VALUE. It passes the integer expression directly to the existing interest-update function. No backend was disabled.

`nio4r-2.7.5-filc.gem` was built from the upstream gem with that patch. Its SHA-256 is `8e2b6399a320ae6bf540f2dc50529962ca552f54f4cf72972facfc23220174b9`.

To reproduce the package: fetch and unpack upstream nio4r 2.7.5, apply the patch with `patch -p1`, export the original gem's specification with `gem specification <original.gem> --ruby`, and build the patched directory with `gem build`. Install the resulting gem using the Fil-C Ruby, not the system Ruby.

The `probes/ruby/nio4r.rb` probe checks interest changes, readiness, data transfer, deregistration, and cleanup on epoll, poll, and select. Each backend completes 100 readable events with explicit collections. Linux AIO and io_uring were not tested. This is not nio4r's full upstream test suite.

## Puma 8.0.2

Puma builds without source changes against the patched nio4r. The `probes/ruby/puma.rb` probe serves 100 POST requests from five concurrent keep-alive clients. Every request forces collection and checks the response path and request-body SHA-256. The server shuts down synchronously afterward.

Logs are in `../../ta/nio4r-install-fixed.log`, `../../ta/nio4r-runtime.log`, `../../ta/puma-install.log`, and `../../ta/puma-runtime.log`.

The same patched source gem and Puma were compiled from scratch inside the current `ruby-filc:4.0.7-78e4bb7` Docker image. All three nio4r backends and the 100-request concurrent/forced-GC Puma probe pass: `../../ta/image-runtime-78e4bb7.log`, combined status 0. The image uses `/usr/local/bundle` as GEM_HOME. Earlier image results remain in `../../ta/image-runtime-70c5604.log` and `../../ta/puma-image-4.0.7.log`. These images use released optfil 0.686. The separate coherent source-built toolchain now also compiles both gems into a fresh gem directory and passes the same probes: `../../ta/current-toolchain-runtime.log`, status 0. It retains only its own installation's bundled gems alongside the new builds. This is still probe coverage, not the full gem suites, Rails, TLS/cluster or long-running validation; that Ruby's full test-all run still has an OOM kill.

This does not establish full Rails application compatibility, clustered Puma behavior, TLS behavior, or long-running leak freedom.

## Ruby 4.0.9 follow-up

Fresh nio4r 2.7.5 and Puma 8.0.2 native builds pass these probes in the clean Fil-C 0.687 image with the shape-cache improvement. A separately built, unmodified GCC Ruby 4.0.9 control uses the same gem sources and its own native extension binaries. The checked order-processing HTTP workload and RSS comparison are documented in [puma-memory.md](../puma-memory.md). The requested 5% memory target is still unmet; these results do not establish leak freedom.
