# Goal

Run Puma reliably and without memory leaks on Ruby 4.0.9 compiled with Fil-C, with no more than a 5% penalty to memory, throughput or latency compared with equivalent stock Ruby 4.0.9.

Acceptance requires all of the following on matched workloads and resources:

- Whole-process median and sampled-peak RSS at most 105% of stock.
- Checked request throughput at least 95% of stock.
- HTTP latency at p50, p95 and p99 at most 105% of stock.
- Correct responses, clean shutdown, sustained-run stability and evidence that objects and resources are reclaimed when no longer needed.

Preserve Ruby behavior and Fil-C safety checks. Count code, metadata, stacks and allocator overhead in memory measurements. Do not inflate the stock baseline or use forced collection or scavenging during acceptance rounds. Memory savings cannot compensate for a performance regression, and passing a finite benchmark alone does not establish reliability or leak freedom.
