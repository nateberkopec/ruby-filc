# Hash and Set entry retirement candidate

`hash-retirement-ruby-4.0.9.patch` is an isolated candidate applied after the consolidated Ruby 4.0.9 port (source commit `b0f3fbf`). It is not included in either default export. It preserves Ruby behavior and Fil-C safety checks; no workload, GC policy, capacity limit or acceptance threshold is changed.

## Retention defects

Fil-C traces pointer capabilities throughout an allocation, not just the slots Ruby considers live. Several table paths leave removed objects reachable:

- Small Hash entries clear the key but leave the value; `Hash#clear` resets bounds without retiring entries.
- `st_table` and Set entries mark only the hash as deleted, leaving their key/value capabilities intact.
- In-place table compaction copies surviving entries toward the front but leaves duplicate capabilities beyond the new bound.
- Resetting embedded Hash table storage with compiler-optimized ordinary `memset` does not guarantee capability retirement when stores become scalar operations.

Ruby sometimes replaces or shrinks an entire table after deletion, masking these defects for particular sizes and methods. Direct C-API coverage is necessary: a caller of `st_clear` need not also trigger Ruby Hash's compaction policy.

The 44 inserted lines clear small Hash values on removal, explicitly clear retired/reset storage with `zmemset`, clear deleted `st_table`/Set entries, and clear the unused suffix after in-place compaction. Deleting callbacks use the key saved before invocation instead of rereading a slot the callback may already have cleared. Ordinary deletion clears only the removed entry; compaction clears its vacated suffix. Headers, private GC fields, capacity policies and non-Fil-C behavior remain unchanged. `st.c` includes `<stdfil.h>` explicitly because the parser also includes that implementation without Ruby's usual headers.

## Focused validation

Every lifetime case retires its allocating thread, retains the container, runs three full/immediate diagnostic collections, and verifies the exact remaining objects. It also verifies surviving contents/order and reuse; Hash/Set cases check retained instance variables, and Hash checks its default value. These forced collections are diagnostic tests, not Puma acceptance rounds.

| Probe | Cases | Stock failures | Baseline Fil-C failures | Candidate Fil-C failures |
|---|---:|---:|---:|---:|
| `hash-delete-lifetime.rb` | 52 | 0 | 41 | 0 |
| `set-delete-lifetime.rb` | 44 | 0 | 10 | 0 |
| `st-table-lifetime.rb` | 36 | 0 | 36 | 0 |
| `table-compaction-lifetime.rb` | 3 | 0 | 3 | 0 |

Hash/Set matrices cover sizes 2, 8, 9 and 100, partial/complete removal, deletion, filtering, clearing and replacement; Hash also covers shifting. The native table matrix exercises direct deletion, shift, `st_update` deletion, `st_foreach` deletion and clearing without automatic Hash compaction. The three compaction cases create holes in a full table, insert again, then remove some of the moved entries while retaining the rest. Hash and Set use colliding keys there.

`table-delete-during-iteration.rb` additionally passes 24 cases on stock, baseline and candidate: small/large Hash/Set collections with colliding keys, deletion of the current entry, clearing during iteration and nested deletion. It checks exact visitation and final contents, including a comparator that rejects reads of cleared keys.

The first candidate passes all 2,044 bootstrap tests and 360 Hash/Set/C-table tests (13,094 assertions, zero failures/errors, 11 skips), but an additional direct C-API case catches a regression those suites miss: a callback can delete/reinsert its current entry and then return `ST_DELETE`. Rereading the now-cleared old slot causes a repeated visit instead of removing the replacement. The final patch uses the saved pre-callback key in both table traversal implementations. `st-table-iteration-delete.rb` fails on the first candidate and passes on stock, baseline and corrected candidate. It deliberately avoids a table rebuild, which can legitimately change traversal; an earlier larger test matrix incorrectly assumed otherwise on stock.

The corrected normal build passes all 2,044 bootstrap tests and the same 360 tests/13,094 assertions, with zero failures/errors and 11 skips. An otherwise pristine GCC build with the candidate also passes all 2,044 bootstrap tests; its temporary source edits were restored, and the installed stock benchmark control remains unchanged.

An independent checked build reconstructs the verified release archive plus the consolidated port, array-shrink candidate and this table candidate, with `VM_CHECK_MODE=1` and `VM_DEBUG_BP_CHECK=1`. Its initial build was stopped for the callback correction, its three changed table files were compared against the normal source, both incremental patches passed reverse apply checks, and validation resumed. It passes all 2,044 bootstrap tests, the Array/Hash/Set/Ractor/C-table selection (851 tests, 35,309 assertions, zero failures/errors, 27 skips), all 135 table lifetime cases, all 53 array lifetime cases and all 25 callback cases. The first checked lifetime launcher could not load Open3 from the uninstalled prefix after its Ruby suites had passed. All lifetime cases were then invoked directly on the checked build-tree executable; the successful suites were not rerun or relabeled.

The first normal build failed for the missing parser-side `zmemset` declaration, then passed after adding the conditional include. Initial launchers referenced an unavailable old bootstrap Ruby; corrected launchers use the verified stock installation. Another launcher incorrectly propagated the Fil-C library override to that stock bootstrap driver, causing a startup failure; final suite commands run without the override. These failed attempts are preserved, not counted as passes.

No full-suite, sustained Puma or memory/performance acceptance is established.

## Matched Puma comparison

Fresh stock/baseline/candidate runs each check 70,000 responses, with 30 measured rounds of 2,000 requests and one-second idle intervals. They use the same container sequentially, 4 GiB/no swap, server CPUs 0-3 and client CPUs 4-7. No builds run concurrently and no application GC/scavenging occurs during acceptance rounds. The measured candidate is the isolated normal table fix, not the combined checked build or the short-string experiment.

| Metric | Stock | Baseline Fil-C | Table candidate |
|---|---:|---:|---:|
| Median RSS, KiB | 36,316 | 189,648 | 189,780 |
| Sampled peak RSS, KiB | 39,164 | 197,444 | 197,408 |
| Checked requests/s | 3,484.1 | 771.2 | 772.5 |
| HTTP p50, ms | 1.201 | 5.969 | 5.960 |
| HTTP p95, ms | 2.373 | 11.423 | 11.439 |
| HTTP p99, ms | 3.375 | 14.952 | 14.994 |

The before/after differences are small and do not establish a repeatable performance effect. The candidate still uses **5.226x stock median RSS**, delivers **22.2% of stock throughput**, and fails every RSS/throughput/latency gate. Stock also fails the warmed-growth screen (+13.1%); the candidate passes at -4.1%. Maximum round client CPU utilization is 27.0% for stock and 6.7% for the candidate, below the 80% limit. All responses and shutdowns succeed. These results fix neither the stock warmup/growth screen nor the overall objective, and are not general leak-freedom evidence.

Receipts: `ta/puma-hash-retirement/` and `ta/puma-hash-retirement-driver.*`. The comparator exits nonzero for the failed acceptance gates even though the measurement driver succeeds.

## Reproduce focused checks

Use matching native extensions for each Ruby/compiler pair. From the repository root, with the selected Ruby on PATH and its native build dependencies available:

```sh
mkdir -p tmp/st-table-extension
cp probes/c/st-table-lifetime/* tmp/st-table-extension/
(cd tmp/st-table-extension && ruby extconf.rb && make)
ruby probes/ruby/hash-delete-lifetime.rb
ruby probes/ruby/set-delete-lifetime.rb
ruby -I tmp/st-table-extension probes/ruby/st-table-lifetime.rb
ruby -I tmp/st-table-extension probes/ruby/table-compaction-lifetime.rb
ruby probes/ruby/table-delete-during-iteration.rb
ruby -I tmp/st-table-extension probes/ruby/st-table-iteration-delete.rb
```

Use separate build directories for stock and Fil-C. The Fil-C toolchain must be available at its configured prefix. The normal candidate was tested by running the installed baseline executable with `LD_LIBRARY_PATH` selecting the candidate library and both matching soname symlinks; the control installation was not overwritten. Parent drivers stop at a failing case. To enumerate baseline failures, invoke each case separately: operation, size and `partial`/`empty` for the first three probes, or `hash`/`set`/`native` for compaction. `clear` has only an `empty` case.

Final patch SHA-256: `3df458bab59c48f4056f6b31a9272dc9b565dbb42c84efe0eb83ce035a60a9e2`. Normal library SHA-256: `db3fec113de54dcb1c55f87685eafb084d157e5f9835ee5ae6a369dcf2ec64fc`. The first candidate library is retained separately for the negative callback control. Combined checked library SHA-256: `a7cac75f743ffe50a0fc0159159ff376ccfdc266113215c293a185dbd3191f26`.

Local receipts: `ta/{hash-delete,set-delete,st-table}-{stock,filc-baseline,candidate}.log`, `ta/table-compaction-*.log`, `ta/table-delete-during-iteration-*.log`, `ta/st-table-iteration-*.log`, `ta/hash-retirement-*`, and `ta/array-hash-checked.*`. Raw builds/logs remain ignored; the patch and reproducible probes are tracked.
