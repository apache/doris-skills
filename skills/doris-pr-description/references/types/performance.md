# Performance

Title tag: `opt`. Use when the main purpose is to make something faster or cheaper (latency, throughput, CPU, memory, I/O, network) with no intended change in results or semantics. If the PR also changes behavior, it is an Enhancement with a Results field.

## What reviewers check

- Is there data behind the claim, and does the benchmark resemble real workloads? Missing numbers are the most common gap: reviewers ask for them on about one Performance PR in ten.
- Is the gain worth the complexity it adds?
- Are results, semantics, and protocols unchanged?
- Where does it not help, or get slower?

## Background

How the slow path works today: what it does for each query, row, or batch, and the data structures involved.

## Problem Summary

Which workload is slow, and by how much, and the gain in one sentence.

## Details

- **Why it was slow** (required): the bottleneck, and how you know: a profile, a flame graph, a counter, or the code itself when the cost follows directly from it, such as a call that walks a whole bitmap for every batch.
- **Optimization** (required): the main idea, and the key data structure or algorithm change.
- **Results** (required): before and after numbers, with the workload, data size, hardware, and how they were measured: QPS, P50/P95/P99 latency, elapsed time, CPU, memory, I/O, rows scanned, network. Use a small table for several measurements. If the gain applies only to tail latency or to one scenario, say so, so that readers don't generalize it.
- **Applicability and cost** (required): when the optimization takes effect and when it doesn't; the extra memory, CPU, I/O, or storage it costs; workloads that may get slower; the complexity it adds. If it sits behind a switch, name the switch and its default.

## Testing

Show that results and semantics are unchanged: the existing suites that cover the path, comparisons with the old code path, and new tests for any path the optimization adds, such as a fallback. Benchmark numbers belong in Results, not here.

## Establish during development

What only development can establish, for the handoff file (`references/development.md`):

- The bottleneck, before optimizing: a profile, a flame graph, a counter, or the code itself when the cost follows directly from it.
- Before and after numbers from the same build type, data, configuration, and hardware, with the number of runs and the revision measured. Benchmark on a `RELEASE` build; Doris builds default to `ASAN` (`AGENTS.md`).
- A workload where the optimization should not help, measured too, to show that it does not get slower.
- That results are unchanged: the suites that cover the path, and a comparison with the old path where one is cheap.
