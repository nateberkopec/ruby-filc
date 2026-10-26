# Workspace recovery

The expected `/tmp/ruby-filc` workspace was absent when work resumed. Docker was already responsive, so the approved OrbStack restart was not performed. The original Ruby containers were stopped. The toolchain container reported exit 255 and OOMKilled=true; that does not identify which interrupted workload caused the flag or explain the missing host directory.

Recovered work is now under `~/src/tries/2026-10-27-ruby-filc`. Existing Docker images and the `ruby-filc-toolchain-data` volume were inspected read-only. No original container was restarted, no volume was removed, and no missing host bind directory was silently recreated.

## Verified artifacts

| Artifact | SHA-256 |
|---|---|
| Pristine Ruby 4.0.7 archive | `47ef59413f7a4587ba6a6b78b14036eb5e36eec2ec0b90964801e88d56a3d375` |
| Consolidated port through historical 78e4bb7 | `8f1c5499c82289007f59bb04c4507b4d0fa9780d74153737ff1c128706e47f71` |
| Revised three-file VM-stack patch | `9147af50928511bfe5b0e6b171228324c814b59ca33c6ad9bcaf18eec37023f6` |
| optfil 0.686 Linux ARM64 archive | `ab3365499571b5e62513247467a7450cd8e02bb915d6bd0b5f49433f25c52cf6` |
| Patched nio4r 2.7.5 source gem | `8e2b6399a320ae6bf540f2dc50529962ca552f54f4cf72972facfc23220174b9` |

The pristine Ruby archive, consolidated patch and compiler archive came from the existing build image. The newer source/build trees, baseline and candidate binaries, native dependency sources, and gem cache survived in the toolchain volume. A local snapshot preserves those Ruby trees and related files; compiler binaries remain in the existing volume.

Applying the recovered consolidated patch to the verified pristine archive, then regenerating its Git diff, reproduces its exact original hash. Comparing the surviving three modified VM files against that baseline reproduces the exact reviewed incremental patch hash. This establishes recovery of the code, not correctness of every behavior.

The original local Git object history was not recovered. The restored source worktree has new commits:

- `a02262d`: verified pristine Ruby release.
- `6d5787c`: consolidated port, tagged `filc-78e4bb7-recovered`.
- `e94ca96`: reviewed VM-stack candidate on branch `vm-stack-retirement`.

These are local reconstruction commits, not substitutes for the original commit identities. The public outer repository tracks the patches, build example, probes and notes; the nested source worktree is reproducible and ignored.

Successful retained file writes, exact edits, and complete reads recovered 125 text files, including review reports. The replay reported no unresolved edits. Raw session records are private recovery inputs and are not included in Git. Generated artifacts were recovered from surviving files where possible rather than invented from summaries.

The nio4r patch was reconstructed by comparing the upstream source gem with the recovered patched gem. The OpenSSL BIO-formatting test patch was reconstructed from the verified original archive and surviving patched test source. Applying each reconstructed patch reproduces its recovered destination byte-for-byte. This does not change the previously unresolved OpenSSL secure-allocation and symbol-export failures.

## Fresh recovery checks

- Both consolidated patch copies match the original checksum and apply to pristine Ruby.
- A clean `port/prepare-source.py --candidate` run creates the same complete source Git tree as the recovered worktree: `c0f90ce9f7090e16541a6d0a90caab8e7dd41f7e`.
- The recovered newer-toolchain normal and checked miniruby binaries each pass all nine VM-frame-retirement scenarios, using a read-only compiler volume and 8 GiB/no-swap/CPUs 0-3.
- The outgoing-only forwarding/tail-call probe passes on baseline, normal candidate and checked candidate binaries.
- The bidirectional forwarding/tail-call probe exits 133 with a safety trap on all three. The earlier stock macOS Ruby 4.0.5 control raises an argument-count error. This is not a regression unique to the VM-stack patch; stock Linux 4.0.7 comparison remains required.

Fresh local evidence is under `ta/recovery-*`. The diagnostic driver completed all cases; its shell completion is not an all-tests-pass verdict. Individual failing statuses are preserved. Original raw suite logs under the lost `ta/` directory were not recreated from remembered results. Historical numbers in STATUS and review reports remain historical observations.

## Resume work

1. Publish and preserve the recovered source artifacts and record future work in Git.
2. Run a stock Linux 4.0.7 control for the forwarding/tail-call trap and fix the verified root cause without weakening either test mode.
3. Recreate a writable development container with this durable workspace mounted at `/work`; the old stopped container still references the missing temporary directory.
4. Restore path records from inspected surviving directories, then complete candidate test-all, specs, C-API, native-gem checks and controlled pressure comparisons.
5. Continue the remaining compatibility and resource work. Recovery and publication do not complete the Ruby/Fil-C goal.
