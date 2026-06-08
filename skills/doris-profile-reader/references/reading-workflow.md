# Doris Profile Reading Workflow

## 1. Confirm Profile Shape

Start from the query id, elapsed time, SQL, FE `Summary`, `Execution Profile`, `MergedProfile`, and `DetailProfile`.

- Use `MergedProfile` first to find candidate fragments/operators quickly.
- Use `DetailProfile` to check skew, per-instance outliers, and whether a large merged time is just parallel accumulation.
- Use the plan text to map operator names back to tables, join sides, grouping keys, exchanges, limits, and runtime-filter direction.
- If the plan has joins, keep two layers in the analysis: immediate runtime bottleneck and plan-shape cause. A scan or hash build may be the active cost while a bad join order/RF direction is the reason that cost exists.
- Keep query-lifecycle time separate from BE operator work. FE `Plan Time`, `Schedule Time`, `Wait and Fetch Result Time`, and client/result fetch time can explain wall-clock latency, especially for small or empty queries, but they are not scan/join/aggregation CPU. If they dominate, report them as a separate lifecycle finding before ranking BE operators.
- If `Is Cached: Yes`, `Total Instances Num: 0`, or the BE detail is absent, the profile is not enough for operator bottleneck analysis. Re-run with profile enabled and SQL cache disabled.
- If the file is an async-profiler/flamegraph, FE metadata-load profile, log excerpt, or other non-runtime-profile artifact, first state that artifact type and diagnose only what it proves. Do not map an FE load-image/auth CPU flamegraph to a BE scan/join/storage slow-query root unless the task also provides the matching runtime profile.
- If multiple profile files are provided, assign each file its own dominant finding before looking for a shared root. A profile dominated by rowset sync, another by sort dependency, and another by scanner wait should remain three findings unless the profile evidence proves they share one cause.

## 2. Build a Counter Classification Before Ranking

Classify each large counter before interpreting it:

- Active work: `ExecTime` after qualifying child wait evidence, plus direct operator custom timers such as scan CPU, hash table build/probe, sort, aggregation, serialization, compression, I/O, decompression, spill read/write.
- Data volume: `InputRows`, `RowsProduced`, `RowsRead`, `ScanRows`, `ScanBytes`, bytes sent/received, blocks produced.
- Wait/backpressure: `WaitForDependencyTime`, `WaitForDependency[...]Time`, `WaitForDataN`, `DataArrivalWaitTime`, `FirstBatchArrivalWaitTime`, `WaitForRpcBufferQueue`, `WaitForBroadcastBuffer`, local-exchange buffer waits, `PendingFinishDependency`, `WaitWorkerTime`, memory reserve waits.
- Resource pressure: memory peak, spill counters, scanner queue wait, remote/local bytes, cache miss/read timers.
- Optimizer/context info: join type, colocate/shuffle flags, partitioner, grouping keys, runtime-filter info, predicates, projections.
- Query lifecycle/context: FE plan time, schedule time, wait/fetch result time, result sink/client fetch time. Useful for wall-clock explanation, not proof of BE operator cost.
- Session/config context: changed or non-default variables, query memory limits, memory percentage, parallelism knobs, local shuffle, two-phase read, runtime-filter wait, SQL cache, and scan parallelism settings. These can be root-cause evidence when they explain why otherwise normal operators underuse resources or hit memory.

Only active work, data volume, and resource pressure can directly support a bottleneck claim. Wait/backpressure counters explain pipeline shape and symptoms, not direct operator cost by themselves.

## 3. Rank Candidate Bottlenecks

Use this priority order:

1. Query elapsed and the largest active operator families.
2. Large rows/bytes that explain the active time.
3. Skew in `max` versus `avg` or a single instance much slower than peers.
4. Spill, memory peak, and queue/thread waits.
5. Runtime-filter effectiveness and wait.
6. Network/exchange serialization, compression, remote bytes, and send-RPC latency.
7. Init/open/close only if they remain large after excluding parallel accumulation and waits.

Do not rank by the largest wait-like counter. A profile where `EXCHANGE_OPERATOR WaitForData0` is the largest counter commonly means the exchange waited for upstream data.

When several scans or branches each contribute meaningful rows, bytes, memory, or active time, do not force a single-operator bottleneck. First summarize the branch family or operator family, then name the strongest member only as an example or leading contributor.

After ranking the direct cost, perform a join-order pass for multi-join plans. Identify build/probe sides, RF source/target sides, and whether a more selective branch was scheduled too late to prune a large scan or build. Use `join-order-diagnosis.md` for the decision rules.

Before writing the conclusion, run these secondary-cause passes when their trigger appears:

- Paired-profile diff: if slow/fast, old/new, internal/external, or rewritten profiles are provided, compare join order, pruning, `instance_num`, scan rows, intermediate rows, exchange distribution, and sink layout. Treat consistent profile differences as root-cause evidence, not optional uncertainty.
- Distribution-layout pass: if scan fanout, exchange/local-exchange/table-sink skew, point-query latency, or insert skew appears, check bucket key, bucket count, random bucket mode, target bucket assignment, hash distribution expressions, hot values, and whether query predicates can prune buckets/tablets.
- Expression drilldown: if projection, UDF, residual join conjunct, or string expression work is hot, map the expression text back to function families and source tables; then ask whether join order, `GLOBAL LIMIT`/`GATHER`, or `instance_num=1` amplified that expression.
- Runtime-filter cause chain: if RF pruning is weak or late, trace both target-side scan behavior and producer-side readiness. A slow RF producer scan can be the root cause of target-side scan volume.
- Storage/RPC dominance: if LazyRead/FileCache/remote IO or `DATA_STREAM_SINK_OPERATOR` RPC time dominates elapsed time while local active CPU is small, promote that path above generic data-volume explanations.
- Memory/OOM ownership: if the query timed out after spill, hit `MEM_LIMIT_EXCEEDED`, or has large peak memory/reservation waits, identify the owning state before naming the cause. Compare hash-join build memory, probe/intermediate rows, aggregation hash/state memory, sort buffers, table-sink buffers, exchange buffers, and expression materialization. For `group_concat`, `array_agg`, distinct, or ordered aggregates, check whether many aggregate states or map-side partial aggregation explain memory better than join row count alone.
- Session/config sanity pass: before deciding on bad join order, worker starvation, or RPC/network outlier, check whether changed settings already explain the shape: disabled parallel scan, very small `parallel_pipeline_task_num`, low `MAX_MEMORY_PERCENT` or query memory limit, disabled two-phase read, disabled local shuffle, disabled runtime-filter pruning, or SQL cache state.

Hard-stop checks:

- Do not finalize a volume-only INSERT/scan explanation until you have searched the SQL/plan text for string-heavy expressions and table-sink distribution keys.
- If a massive INSERT/SELECT has visible `SPLIT_BY_STRING`/`cardinality(split_by_string(...))`, do not finalize sink/backpressure as the primary root until you compare the string-expression row count and per-instance progress skew against sink active write timers.
- Do not finalize a string-expression root in paired-profile INSERT/SELECT tasks until you compare resource knobs, `instance_num`, tablet/receiver distribution, and target bucket layout across profiles. Expression work can be the direct CPU while expansion, tablet imbalance, or low parallelism is the root layer.
- Do not finalize an OOM as `join explosion` merely because join rows are large. First check whether aggregation state count, ordered aggregate functions, expression materialization, spill buffers, or session memory limits better explain the memory peak.
- Do not finalize a scanner-worker contention explanation until you have decided whether bucket/tablet pruning failed.
- Do not finalize a runtime-filter pushdown/pruning explanation until you have checked whether the RF producer or peer scan was delayed by large `ScannerWorkerWaitTime`, `PerScannerWaitTime`, or scan thread saturation.
- Do not finalize an INSERT skew explanation until target bucket/key design, write bucket count per BE, and hot distribution values are either named from the profile or listed as the root-layer validation.
- Do not finalize an RPC/backpressure explanation in a multi-profile task until you have compared plan shape and `instance_num` across profiles.
- Do not finalize an RPC/backpressure explanation for a timeout or memory-resource issue until you have checked spill and memory settings. When low memory limits or memory percentage explain why operators cannot make progress, exchange waits are usually symptoms of resource pressure.
- Do not discount `SORT_OPERATOR_DEPENDENCY` automatically when the SQL/profile has `ORDER BY LIMIT`, TopN, late materialization, or two-phase-read settings. First decide whether sort dependency is the primary lifecycle blocker, then trace why the sort source was blocked.

## 4. Interpret Merged Timers Correctly

Merged profile values often include `sum`, `avg`, `max`, and `min`. Treat them differently:

- `sum` can exceed wall-clock elapsed time because it accumulates across parallel fragments, drivers, scan ranges, and scanner threads.
- `max` is usually better for wall-clock suspicion.
- `avg` plus `max` reveals skew.
- `min` is useful only for skew context.

If an operator appears many times, a long summed `ExecTime` may represent normal parallel CPU. Compare per-instance `max` to query elapsed and compare rows/bytes per instance.

## 5. Read Pipeline Waits as Dependencies

Pipeline tasks register wait/dependency counters for start prerequisites, upstream data readiness, downstream write availability, memory reservation, runtime filters, and local/remote queues. These counters answer "what was this driver waiting for", not "where CPU was spent".

Examples:

- `WaitForDependency[OLAP_SCAN_OPERATOR_DEPENDENCY]Time`: scan source was blocked by its dependency state.
- `WaitForDependency[HASH_JOIN_BUILD_DEPENDENCY]Time`: probe/build sequencing or shared build state dependency.
- `WaitForData0`: exchange source waited for sender queue data.
- `WaitForRpcBufferQueue`: exchange sink waited for RPC buffer capacity.
- `WaitForLocalExchangeBufferN`: sender waited for a local exchange channel.
- `WaitWorkerTime`: pipeline task waited for worker scheduling.
- `ScannerWorkerWaitTime`: scanners waited in the scan worker pool.

Large waits are actionable only after you identify the upstream/downstream resource that caused them.

In multi-profile tasks, apply that rule per profile. A wait counter that is a symptom in one profile can be the dominant recorded blocker in another profile if the corresponding active branch, TopN/two-phase read path, rowset sync, or memory-resource setting differs.

## 6. Diagnose by Operator Family

Use the operator guide and choose the family-specific proof:

- Scan bottleneck: high scan active time plus large `ScanRows`/`ScanBytes`, high `ScannerCpuTime`, I/O/decompression/lazy-read/predicate timers, or scanner queue wait.
- Scan/RF latency trap: if scan `ExecTime` is close to `RuntimeFilterInfo` `RFx WaitTime`, `AcquireRuntimeFilter`, or `WaitForRuntimeFilter`, treat the scan as waiting for filters, not spending CPU in storage. Detail profiles can expose `WaitForRuntimeFilter` even when merged `RFx WaitTime` is zero or the filter timed out. `TOPN OPT`, `TopNFilterSourceNodeIds`, or `SharedPredicate` on a scan should be read as the same filter-wait family before blaming storage CPU. Then decide whether the wait was justified by `FilterRows` and downstream savings.
- RF plus scanner-wait trap: when RF is not pushed down or arrives too late, and the producing or peer scan has very large `ScannerWorkerWaitTime`/`PerScannerWaitTime`, report the chain explicitly: scan thread/scheduling delay slowed RF readiness or scan progress, which made zonemap/storage pruning ineffective. Do not describe the case only as a target-side RF-pushdown miss.
- Join bottleneck: high build/probe active time, large build/probe rows, hash table memory, non-equi conjunct time, runtime filter publish/build, or spill in partitioned join.
- Aggregation bottleneck: high build/merge/hash-table times, large `InputRows`, large hash table size/memory, or spill.
- Sort/window bottleneck: high sort/evaluation active time, large input rows, memory pressure, or spill.
- Exchange bottleneck: high serialization/compression/send/receive/merge time, high `RpcMaxTime`/`RpcAvgTime` on `DATA_STREAM_SINK_OPERATOR`, and bytes. If `RpcMaxTime` is near query elapsed or dominates serialize/compress/local-send timers while `BytesSent`/`RpcCount` are non-zero, keep the data stream sink as a bottleneck candidate and mention it in evidence even when local CPU timers are small. If local sender CPU and downstream active timers cannot explain the elapsed time, prefer RPC/BE-to-BE transfer or receiver outlier over plan-shape volume as the primary cause; row volume is then an amplifier. Data-arrival waits alone are not enough.
- Sink/write bottleneck: high append/write/commit/close/load timers and bytes/rows. Output `PendingFinishDependency` alone is not enough.

For repeated CTEs, repeated common subplans, expanded `UNION ALL` branches, or scalar-subquery fan-in plans, do not summarize from one representative branch. Build a small branch inventory: table/source, scan rows/bytes, rows produced, major join/aggregation rows, memory/spill evidence, and whether the apparent time is active work or RF/dependency wait. Then aggregate the pattern mentally. Repeated branches can make the true bottleneck "many medium scans plus RF waits" rather than one single giant operator. A branch with the highest apparent wall time may only be waiting for RFs; still report sibling branches with large scan volume, large output rows, or heavy aggregation/join memory. In scalar-subquery fan-in plans, top-level `CROSS_JOIN_OPERATOR` instances may only combine one-row branch results; a multi-second `CROSS_JOIN_OPERATOR` dependency wait usually means the cross join waited for slower child branches, not that nested-loop join CPU dominated.

Small dimension scans often show high apparent `ExecTime` or detail scanner timers because they waited for runtime filters or because merged counters accumulate across many tiny scanners. Before promoting a dimension scan over a fact branch, compare rows/bytes, branch role, output impact, and whether the timer is mostly RF wait. If the fact branches dominate row volume or downstream aggregation, report the dimension scan as supporting/filtering work instead of the main bottleneck.

## 7. Runtime Filter Pass

If runtime filters appear, always answer:

- Which join/build side produced the filter.
- Which scan/probe side applied it.
- Whether it filtered rows, was always true, arrived too late, or forced meaningful wait.
- Whether a long wait is justified by saved scan work.

See `runtime-filters.md`.

## 8. Join Order Pass

For every multi-join profile, always answer:

- Which side each important join builds on, and which side probes.
- Whether the build side is unexpectedly large compared with the probe/other available side.
- Whether runtime filters flow from a selective side to a large scan early enough to save work.
- Whether paired profiles, hints, rewritten SQL, memo estimates, or actual rows prove a better order.
- Whether memo contains an unchosen reversed join expression, or schema/distribution keys show that the current RF source should instead be an RF target.

If the active bottleneck is a scan or hash build that would disappear under a better join order, report the scan/build as the runtime bottleneck and the join order/RF direction as the likely root cause.

When multiple profiles are present, build a tiny differential table mentally before judging uncertainty: slow profile bottleneck, fast profile bottleneck, row-count change, `instance_num` change, pruning change, and distribution change. If the fast profile removes the direct bottleneck by changing join/pruning/parallelism/distribution, the root cause is that plan-shape difference, not merely the slow profile's largest operator.

When only a slow profile is available, still make a join-order judgment. Use "likely" when the evidence is circumstantial, but do not answer "not proven" merely because there is no paired fast profile. Empty probes, empty final results after huge build/scan work, huge intermediates later eliminated, and RF-source inversion are enough to call the order likely bad when build/probe/RF sides and row counts are visible.

Use this red-flag pass before writing the conclusion:

- Expensive RF source emits empty/tiny RF and all targets skip: join order/RF direction is likely bad, not proven good.
- Huge build/shuffle before zero/tiny probe or result: build/probe order or build scheduling is likely bad, even if another predicate explains why the probe is empty.
- Huge intermediate before a contradictory or highly selective inner/non-equi join: join order/predicate placement is bad.
- Tiny semi/subquery key set is applied after a large fact scan/build: join order/RF timing is likely bad.

If one of those red flags matches, the conclusion must say `bad` or `likely bad`. Use `not proven` only for the exact alternate legal plan or repair, not for whether the observed order is wrong.

If your reasoning says "plan shape", "predicate placement", "empty probe", "late contradictory predicate", or "expensive RF source", translate that into an explicit join-order diagnosis. The required output is not complete until it says whether the join order/build-probe/RF direction is good, suspicious, or bad.

See `join-order-diagnosis.md`.

## 9. Output Standard

A good profile explanation is evidence-bounded:

- Quote exact operator and counter names.
- State whether each quoted timer is active, wait, or accumulated.
- Tie scan/join/exchange metrics to table or plan node when possible.
- For joins, include a short build/probe/RF-direction judgment, even when the direct bottleneck is a scan.
- Avoid generic tuning advice unless the profile proves the need.
- End with missing evidence if the profile is incomplete.
- If a solution is requested, load `solution-playbook.md` and then `known-issues-solutions.md`. The answer is incomplete if it gives a concrete mitigation without first deciding whether the mitigation is profile-proven, historically recorded, or only a next check.
- Preserve exact recorded solution details. Do not replace a known PR, version, parameter value, or SQL rewrite shape with a broad family such as "upgrade", "collect stats", "use hints", or "rewrite SQL".
