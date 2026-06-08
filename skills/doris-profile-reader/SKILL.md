---
name: doris-profile-reader
description: Interpret Apache Doris query runtime profiles, especially profile bottleneck triage, misleading wait counters, per-operator metric priority, scan, join-order/runtime-filter analysis, and evidence-bounded performance explanations. Use when given a Doris profile, query id, profile URL/text, or a request to explain Doris query performance.
---

# Doris Profile Reader

## Purpose

Use this skill to identify the real bottleneck in an Apache Doris query runtime profile. The core rule is to separate active work from dependency, queue, and backpressure waits before naming an operator as expensive. When the plan contains joins, also separate the immediate runtime bottleneck from the plan-shape cause, especially bad join order and runtime-filter direction.

## Required Reading Order

1. Read `references/reading-workflow.md` for the analysis workflow and output contract.
2. Read `references/counter-semantics.md` for counter meaning and priority, especially wait counters.
3. Read `references/operator-guide.md` for the relevant operator family.
4. Read `references/failure-patterns.md` when the profile shows skew, bad join/distribution choices, weak pruning, sort/spill/resource pressure, external scans/catalogs, lifecycle waits, or when the user expects an issue-level root cause from profile-only evidence.
5. Read `references/join-order-diagnosis.md` when the profile or plan has multiple joins, a large hash/nested-loop build, a large scan that might have been pruned by a join, paired fast/slow plans, hints/reordered SQL, or a request about join shape/reorder.
6. Read `references/runtime-filters.md` when a profile or plan includes `RuntimeFilterInfo`, `RF... <-`, `RF... ->`, `JRFs`, `WaitForRuntimeFilter`, or `AcquireRuntimeFilter`.
7. Use `references/source-profile-inventory.md` as the source-backed operator/counter inventory. If a counter or operator is not in the narrative docs, do not ignore it; look it up in this inventory and classify it by the rules in `counter-semantics.md`.
8. Read `references/solution-playbook.md` when the user asks for a fix, workaround, mitigation, tuning, SQL rewrite, or when the requested output schema includes solution fields.
9. Read `references/known-issues-solutions.md` after the root-cause layer is established and a solution is requested. Use it as historical evidence, not as a replacement for profile diagnosis.

## Non-Negotiable Interpretation Rules

- Do not call `WaitForDependencyTime`, `WaitForDependency[...]Time`, `WaitForData0`, `WaitForDataN`, `WaitForRpcBufferQueue`, `WaitForBroadcastBuffer`, `PendingFinishDependency`, or pipeline blocked/wait counters direct operator compute cost. They are dependency, data-arrival, queue, memory, or backpressure signals.
- Do not discard high `RpcMaxTime`/`RpcAvgTime` on `DATA_STREAM_SINK_OPERATOR` as a generic wait counter. With non-zero `BytesSent` and `RpcCount`, it is exchange/RPC-path evidence; if it is close to wall time or dominates local serialize/compress/send timers, keep it in the bottleneck conclusion and check channel, receiver, or BE outlier skew.
- If a session variable, missing optimization, or large row count explains why data reached an exchange, do not make it the primary slow cause unless local scan/sort/window/join active timers dominate. When `DATA_STREAM_SINK_OPERATOR` RPC time dominates elapsed time, treat the plan/data volume as an amplifier and keep RPC/BE-to-BE transfer as the leading bottleneck candidate.
- When multiple profiles are provided, their differences outrank single-profile wait symptoms. If the slow/fast profiles differ in join order, pruning, `instance_num`, exchange distribution, or bucket/sink layout, diagnose that plan/data-layout difference before blaming generic RPC, scanner, or exchange backpressure.
- If a join/projection hotspot is dominated by wide JSON/VARIANT/string columns from one table and the work is single-instance or heavily skewed, do not stop at expression CPU. State the likely root layer as join order/distribution or cost-model underweighting wide-column work, with expression CPU as the runtime symptom.
- For INSERT/SELECT profiles, visible massive-row `SPLIT_BY_STRING`/`cardinality(split_by_string(...))` expressions are primary root-cause candidates. Do not demote them below generic scan/shuffle/table-sink volume unless independent active sink/write timers dominate.
- For INSERT skew, receiver or UNION/local-exchange skew must be tied back to target bucket count, bucket key, write bucket parallelism, and hot values. If exact DDL is absent, conclude likely target bucket/key design mismatch or insufficient write buckets rather than stopping at exchange skew.
- Before concluding that a full scan or INSERT is slow only because of row volume, search the SQL/plan text for string-heavy expressions such as `SPLIT_BY_STRING`, regexp, trim/replace chains, `INSTR`, `COALESCE`, and `NULLIF`. On massive rows, those expressions remain root-cause candidates even when no `ProjectionTime` counter is visible.
- For point or narrow queries with tiny output but many tablets/scanners, state the bucket/tablet-pruning verdict. High `ScannerWorkerWaitTime` is a fanout symptom unless workload-pressure evidence exists; if predicates and indexes are effective but many tablets are opened, prefer no bucket pruning/table layout over scanner-pool contention.
- Do not rank operators by the largest wait-like counter alone. First rank by `ExecTime`/active timers, direct custom timers, rows/bytes, memory/spill, and skew.
- Before ranking a query bottleneck, verify the profile type. Async-profiler CPU flamegraphs, FE load-image/load-auth profiles, logs, or cached summaries are valid evidence for their own lifecycle hotspot, but they are not BE query runtime profiles. If the file type does not match the requested slow-query question, report the mismatch and ask for the matching runtime profile instead of forcing an unrelated Doris-query conclusion.
- For OOM, timeout-after-spill, or memory-limit profiles, find the memory owner before choosing the root cause: check session/global memory settings, spill state, peak memory by operator, hash-join build/probe memory, aggregation hash/state memory, sort buffers, table-sink buffers, exchange buffers, and expression materialization. Do not call a large join the root until aggregation-state and expression-materialization costs have been ruled in or out.
- Session/config evidence can outrank operator-shape speculation. Explicit non-default settings such as disabled parallel scan, very small `parallel_pipeline_task_num`, low memory percentage/limit, disabled two-phase read, or disabled local shuffle should be evaluated before concluding bad join order, scanner contention, or network outlier.
- Analyze multiple profiles independently before summarizing. For each profile, name its dominant active/wait/resource signal and only then compare them. Do not collapse unrelated profiles into one generic fanout, scan, join, or RPC explanation.
- Keep profile-visible bottlenecks separate from issue-level root causes. If a deeper cause requires schema, statistics, version, config, logs, comments, or a fast/slow comparison that is not present, say what the profile proves and list the exact missing check instead of overclaiming.
- For solution fields, do not convert every plausible validation into a fix. First decide the solution source: profile-proven, exact historical pattern, code-backed but unproven next check, or no historical solution. Preserve exact historical parameter names, values, PR numbers, version numbers, and SQL rewrite shapes when they are in the known-pattern evidence.
- If the diagnosis is uncertain or only profile-level, prefer an empty historical solution plus targeted `next_checks` over a concrete mitigation. A wrong concrete fix is worse than no fix.
- When the requested schema has `historical_solution`, fill it only for `profile_proven` or exact `historical_pattern` actions. If the action still needs validation, or is inferred from a neighboring pattern family, leave `historical_solution` empty and move the action to `next_checks`.
- Treat merged-profile `sum` timers as accumulated across parallel instances. A timer can exceed query elapsed time and still be normal when many scanners, drivers, or fragments run in parallel.
- For scans, prioritize `RowsRead`, `ScanRows`, `ScanBytes`, `ScannerCpuTime`, `ScannerGetBlockTime`, `ScannerWorkerWaitTime`, I/O/decompression timers, predicate/lazy-read timers, and row-filter counters. `ScannerWorkerWaitTime` is important, but it indicates scanner scheduling/thread-pool wait rather than scan CPU.
- For runtime filters, distinguish source/build side from target/probe scan side. In plan text, `RFxxx <- expr` is produced from the build side; `RFxxx -> expr` is applied at a target scan. In profiles, `RuntimeFilterInfo` and scan-side wait/filter counters decide whether the RF helped or just waited.
- For joins, always identify build side and probe/target side before judging the order. A scan can be the immediate active bottleneck while the root cause is still bad join order if a selective join/RF source is scheduled too late to prune that scan.
- When a join/distribution choice looks bad, check estimated versus actual rows, statistics/null/hot-value evidence, join distribution, and RF direction if present. Do not stop at "large scan" or "large build" when the profile exposes a planner/statistics symptom.
- Do not require a paired fast profile before naming likely bad join order. A single slow profile can be enough when it proves large wasted build/scan work before an empty probe/result, an RF source side that had to scan massively before it could emit an empty/tiny filter, or a huge intermediate later eliminated by a highly selective or contradictory join predicate.
- Do not treat "the current RF made other scans wait and then skip" as proof that the join order is good. If producing that empty/tiny RF required the only expensive scan, the RF source/target choice is itself the join-order question.
- When a large build/source side is paid before an empty/tiny probe, preserved side, semi-join key set, or contradictory join can eliminate the result, call the build/probe order likely bad unless the profile proves that ordering is semantically forced and no earlier pruning/short-circuit is possible.
- When `max` is far above `avg` on scan, join, aggregation, exchange, sort, or sink operators, run a skew pass: compare per-instance rows/time/bytes, tablet or bucket assignment, local shuffle, distribution key, and global/session parallelism before calling the cause generic data volume.
- If a strong single-profile join-order pattern matches, do not hedge as "suspicious", "close to likely bad", or "not proven". Use `likely bad` when a better legal order still needs validation, and reserve `not proven` for the exact alternate shape, not for the join-order diagnosis itself.
- When a join query has plan-shape evidence, the answer must explicitly judge join order/build-probe/RF direction as good, suspicious, or bad. Do not replace that judgment with a vague "predicate issue" or "plan shape issue".
- A long `InitTime`, `OpenTime`, `CloseTime`, or profile total can matter, but only after confirming it is not accumulated across many instances and not dominated by a known wait/dependency branch.

## Standard Answer Shape

When explaining a profile, answer in this order:

1. `Conclusion`: one or two sentences naming the likely bottleneck and, when joins are involved, whether the plan shape/join order is likely the cause.
2. `Evidence`: profile counters with operator names, values, and whether each is active work, data volume, wait/backpressure, memory/spill, or runtime-filter evidence.
3. `Reasoning`: how the evidence maps to the execution plan, which side is build/probe or RF source/target, why misleading counters are discounted, and whether the join order is reasonable.
4. `Next checks`: the smallest additional profile/log/code checks needed if the conclusion is still uncertain.
5. `Solution / mitigation` when requested: only name a solution that is directly supported by this profile or by a matching historical pattern in `references/known-issues-solutions.md`. If no historical or profile-proven solution applies, say so and keep the item as a next check instead of inventing advice.

Always preserve uncertainty. Use "proven", "likely", and "not proven" explicitly when the profile lacks enough detail.

## Scripts

- `scripts/extract_source_profile_inventory.py`: scan Doris source for factory-created operators and counter/info registrations.

Scripts are evidence-generation helpers. They do not replace the reading workflow.
