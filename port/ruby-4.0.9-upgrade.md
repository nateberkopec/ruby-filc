# Ruby 4.0.9 / Fil-C 0.687 upgrade

The active build now uses Ruby 4.0.9 and the latest published stable Fil-C release, 0.687. The older 4.0.7 images, source-built compiler and recovered worktrees remain separate controls. They were not overwritten or relabeled.

## Inputs and source state

- Ruby release: [4.0.9](https://www.ruby-lang.org/en/news/2026/10/23/ruby-4-0-9-released/), revision `3e93b23afc`, archive SHA-256 `a8057adb39f51ad6dc3106237504c93dd792bb515837b4fe7817ae21ed7e51f4`.
- Fil-C release: [0.687](https://github.com/pizlonator/fil-c/releases/tag/v0.687), release tag `2db72c646daa1acad2754bcb0e2f220f732e9789`. The compiler reports `clang 20.1.8`, `Fil-C 0.687`, embedded revision `36f07a2f8f8141b3488d7ca20a680fd629886eeb`.
- ARM64 optfil archive SHA-256: `375995867dcd3e91533efba6328a5057e51cf7db5a1ffa413ad391d0336ade6e`, verified before use. This is the glibc distribution, not the musl or Peregrine distribution.
- Latest upstream main at inspection: `b8ffc50327d4fe8c4fe6e4fc2b9d823ed19966d8`. Unreleased main is not substituted for the stable release.
- Local source repository: `ruby-4.0.9-glibc`; pristine commit `ea622839f5b413ba967dcff9357c7141cfc7dcfc`, baseline `229ef4f`, separate VM-stack candidate `2ce7302`.

The baseline port applies without conflicts: 142 files, 2,815 additions and 1,192 deletions. The 4.0.9 class-variable-cache write barrier and extension-unloading changes remain intact. The Docker build excludes the VM-stack candidate.

| Export | SHA-256 |
|---|---|
| Root/example consolidated patch, identical bytes | `fcfe3fe8b54f612accea8eec1c7b1aff640876d3956b6b599a3a783c94b07b11` |
| Rebased VM-stack candidate | `52815422ae52af7d06cc4afbb5d53a94c1f4123d7b18cf5a02fc7e9454a9acdd` |

Applying both exports to a pristine worktree reproduces candidate Git tree `e85e148af1eb76dfd6c362df9207b6032fe3949e`. The old VM-stack review covers the 4.0.7 version, not full acceptance of this new build. Ruby's copied license files are unchanged.

## Fresh validation

The clean ARM64 build completed successfully. It rebuilt Ruby and libyaml against the matching compiler/runtime/libraries in the 0.687 optfil distribution; no older native Ruby extensions were copied in.

- Build image: `sha256:11157e105d84c0f5d3c544cef208f52d10d7afe006aa1ab89eb5956a8e1cb5ba`.
- Runtime image: `sha256:25e8bdf1f7cef2ddfd53ecc72812bba1209005cedba1b2ca369388329b59bc0e`.
- Tags: `ruby-filc{,-build}:4.0.9` and `ruby-filc{,-build}:4.0.9-filc0.687`.
- `mise run --force test`: status 0. Runtime/dependency loading, GC/fibers, HTTPS, native extension compilation/loading, intentional overflow rejection (133), and the cache/callback/concurrency regression runner passed under 8 GiB, no extra swap and CPUs 0-3.
- Both latest-version lints pass. Their six CLI system cases reject stale pins (1), duplicate pins (2), and real connection failures (2), without success output.
- The initial Docker attempt failed because `.dockerignore` still excluded the renamed patch. This packaging failure is preserved; the corrected second attempt succeeded.

Local receipts: `ta/build-ruby-4.0.9-filc-0.687{,-attempt2}.*`, `ta/test-ruby-4.0.9-filc-0.687.*`, and `ta/lint-*-version-before.*`. The before-lint runs reject 4.0.7 and 0.686 rather than treating those old pins as current.

The full unprivileged sequence runs separately in `ruby-filc-validation-4.0.9-0.687`. Bootstrap completed with 1 failure in 2,044 tests (status 2): the GC-stress/fork case `[ruby-dev:32404]` timed out after 180 seconds. A timeout of this case was previously observed on 4.0.7 as well; this does not establish a new 0.687-specific regression. Test-all/spec/C-API continue after the failure. The driver retains the normal exclusion directory, explicitly enables normally excluded leak-test names, disables retries and records each suite's status. No full-suite success is claimed.

## Confirmed remaining failure

`probes/ruby/tail-forward-minimal.rb` still fails on the new versions. A separately built, unmodified GCC Ruby 4.0.9 control uses `/lib/ld-linux-aarch64.so.1`, not Fil-C. Its `plain` mode returns 42 and exits 0; `tail` segfaults with exit 139. The new Fil-C image returns 42 in `plain`, but rejects an out-of-bounds source read in `vm_adjust_stack_forwarding`/`memmove` in `tail`, exit 133.

Receipts: `ta/stock-control-4.0.9-build.*`, `ta/tail-forward-4.0.9-{stock,filc}-{plain,tail}.*`. Thus neither Ruby 4.0.9 nor Fil-C 0.687 eliminates this Ruby VM defect. Fixing it and validating the full runtime remain required.
