# Recurrent Failure Patterns

Use this file to avoid common profile-reading misses. It is not a list of fixed answers; apply only when the profile contains matching evidence.

## Profile-Only Boundary

Many slow-query issues have two layers:

- Profile-visible bottleneck: the operator, wait, skew, or lifecycle phase that consumed time.
- Issue-level root cause: schema, statistics, config, version, deployment, PR/fix, log, or fast/slow comparison evidence explaining why that bottleneck happened.

If the second layer is not in the provided materials, do not invent it. State the direct bottleneck as proven/likely and list the smallest missing checks, for example: table distribution and index DDL, column statistics and estimates, session variables, BE/FE logs, version-specific fixes, external monitoring, or a paired fast profile.

Profile type is also a boundary. A CPU flamegraph, FE load-image/load-auth profile, cached profile summary, or log excerpt can prove a lifecycle or CPU hotspot, but it cannot prove a BE query-runtime scan/join/storage bottleneck by itself. If the artifact type and requested root-cause type do not match, report the mismatch instead of mapping unrelated symbols to a slow-query cause.

For multiple provided profiles, do not generalize before classifying each profile. First write the mental row `profile -> dominant counter/operator -> proven bottleneck -> missing context`; then decide whether the rows share a cause. Mixed rowset-sync, sort-dependency, scanner-wait, and cache profiles should stay mixed unless the evidence connects them.

## Planner, Statistics, And Join Distribution

When a profile shows a huge build side, bad broadcast/shuffle choice, late or inverted runtime filters, or large scan/build work before tiny output:

- Compare estimated versus actual rows when plan or profile includes estimates.
- Check null counts, hot values, NDV, stale/missing column stats, and whether predicates use expressions the estimator cannot model.
- For external/Hive/Paimon tables, compare catalog/table properties or estimated rows with actual `RowsProduced`/raw scan rows. A tiny catalog row count with millions of scanned rows is a stats/property root-cause signal, not just a bad join symptom.
- Separate direct cost from cause: the direct cost may be scan/build/probe, while the cause may be row-count misestimation or join distribution choice.
- Do not automatically call RF-after-the-fact selectivity a wrong join order if the profile or issue evidence says the cost model had no way to use that future RF selectivity.
- For non-equi, `CASE`, `LIKE`, `INSTR`, `COALESCE`, `NULLIF`, `TRIM`, `REPLACE`, and similar residual join predicates, do not default to join-order speculation. Treat residual expression CPU as the likely root cause when removing or rewriting that expression is the natural profile explanation.
- If an equality join on a semantically low-cardinality key creates a disproportionate intermediate result, especially with high memory or shuffle, run a key-skew/cardinality pass. Hot values, poor NDV, stale/missing stats, or large estimate-vs-actual gaps should move the root cause from generic "large join" to skew/cardinality misestimation causing bad join order or distribution.
- If expensive projection is dominated by wide JSON/VARIANT columns or repeated JSON extraction after a join, map the projected columns back to their source table and join position. A wide-column table joined before more selective branches is a join-order/cost-model issue with expression CPU as the direct bottleneck.
- For custom-info/value JSON tables or repeated `get_json_string` projections, do not stop at "JSON expression CPU" if a join-order or build/probe choice caused a single hot instance to evaluate those expressions. Name the likely deeper cause as optimizer/cost-model underweighting wide-column work or placing the wide JSON branch too early, with expression CPU as the runtime symptom.
- If the plan shows a wide JSON/custom-info table brought into a join before later selective branches, and the hot operator spends most time in output projection/casts on that table's value column, make the conclusion two-layered: the profile-visible hotspot is JSON/string/DECIMAL expression CPU, but the root layer is likely join order/distribution or cost model not pricing wide-column expression work. Hints or disabling join reorder are natural validation checks when no fast profile is provided.

## Skew, Bucket Layout, And Parallelism

When `max` is much larger than `avg`, or one fragment/instance dominates:

- Compare per-instance rows, bytes, active timers, and output rows before blaming total data volume.
- Check bucket/tablet count, distribution key, partition pruning result, replica placement, and whether only one tablet or BE receives most work.
- For aggregation/join/shuffle skew, check whether local shuffle is absent or suppressed and whether hash expressions match skewed columns.
- For scanner waits, check global/session parallelism such as pipeline task limits before concluding storage or metadata latency.
- If exchange, union, or table-sink rows concentrate on one receiver or a tiny set of channels, inspect shuffle keys, target bucket count, target bucket key, and hot values before calling the problem generic exchange backpressure.
- If a wide-column, JSON/VARIANT, or UDF branch is single-instance or heavily skewed after a join, check whether join reorder put that wide branch before a more selective join and whether a broadcast/shuffle alternative avoids the skew.
- For INSERT/table-sink skew, do not stop at `UNION_OPERATOR`, `LOCAL_EXCHANGE_OPERATOR`, or a single slow receiver. Inspect target bucket count, bucket key, write bucket count per BE, hash distribution expressions above UNION, and hot values in those keys. Receiver skew aligned with the target/distribution key is a bucket-layout or hot-key root cause.
- If an INSERT profile shows one receiver taking nearly all rows and SQL/profile evidence points to a hot distribution value, make target bucket/key layout mismatch or insufficient write-bucket parallelism part of the conclusion. If exact DDL is absent, say `likely target bucket/key mismatch or hot-key write distribution` rather than stopping at exchange skew.
- If `FILE_SCAN_OPERATOR`, hash join, and a CTE/data-stream producer are all large, compare per-instance max/avg rows and send time before calling it pure data volume. Concentrated scan/join/send work should be reported as data skew causing poor hash join or CTE producer exchange behavior.
- If a hash join over an authorization/mapping/dimension key expands a large fact scan and a CTE/data-stream producer has seconds of send or strong max/avg skew, prefer `data skew causing poor hash join and CTE producer/send long tail` over generic non-unique-key amplification. Non-unique keys explain amplification; skew explains why the profile is slow and uneven.
- For INSERT profiles with paired before/after or rewritten profiles, if the slow version hashes by a business key and one receiver gets almost all rows while the faster version randomizes/null-salts that key, the root is not just exchange skew. State target bucket/key design mismatch, too few effective write buckets, and hot values as the root layer; the randomization is counterfactual evidence.
- When paired profiles differ mainly in global/session parallelism, tablet placement, or expansion-time distribution after cluster resize, make those resource/layout differences the root layer before promoting expensive expressions. String or UDF projection may explain per-row CPU, but it does not explain why the paired profile became faster after parallelism or tablet distribution changed.

## Scan Pruning And Index Use

When scans dominate but predicates look selective:

- Verify whether bucket/tablet pruning is possible from the table distribution keys and query predicates.
- For point or narrow count queries that still open many tablets/segments, check the table distribution key. Hash bucket keys absent from the predicate, random bucketing, or too many buckets can make tablet opening the bottleneck even when predicate filtering is effective.
- In point-query fanout cases, explicitly state the bucket-pruning verdict: `possible`, `not possible`, or `not visible from profile`. If the table uses `RANDOM BUCKETS` or the hash bucket key is absent from predicates, root cause is no bucket/tablet pruning, not generic scanner initialization.
- If tiny-output profiles collectively open approximately the full bucket/tablet set, infer no bucket pruning as the root layer even when the concrete distribution key is not visible. Phrase the missing DDL as validation, not as a reason to stop at "many scanners/segments".
- For inverted index cases, distinguish generic "index not effective" from predicate/index mismatch: tokenized versus non-tokenized equality, `MATCH_REGEXP`, `search()`, `IS NOT NULL` inside compound expressions, `OR` rewrite, VARIANT `LIKE`, and ngram bloom needs.
- Use scan counters such as filtered rows, index query/search time, lazy read time, and storage rows read to decide whether pruning failed or pruning worked but remaining IO/CPU is still high.
- If runtime filters are involved, decide whether the scan waited for the RF or proceeded before the RF arrived. A late producer-side scan can be the cause of poor RF pruning even when the target scan shows large rows.
- High `ScannerWorkerWaitTime` is not enough to conclude cluster/thread-pool contention. If concurrency is low, predicates/indexes are effective, and many tablets/scanners are opened, treat scanner wait as a symptom of scan fanout or bucket-pruning failure unless independent workload pressure evidence exists.
- When active scan CPU/I/O/index work is small per task but `ScannerWorkerWaitTime` is large across many scan instances, explain the wait as scheduling overhead from fanout unless the profile or context proves competing workload pressure. Do not make scanner-pool contention primary merely because the wait counter is large.
- Conversely, if scan rows are huge, RF/zonemap pruning should have reduced them, `RowsZoneMapRuntimePredicateFiltered` or runtime-predicate filtering is zero/tiny, and `ScannerWorkerWaitTime`/`PerScannerWaitTime` is minutes or hours, keep scanner wait/thread-pool pressure in the main cause chain. In that pattern the root is not only `IsPushDown=false`; it is late/ineffective RF pruning plus slow peer/producer scan progress from scanner scheduling pressure.

## Exchange, RPC, And Remote Transfer

For exchange sinks and remote-transfer waits:

- Treat high `DATA_STREAM_SINK_OPERATOR` `RpcMaxTime`/`RpcAvgTime` with non-zero bytes/RPC count as first-class exchange-path evidence.
- `PendingFinishDependency`, data-arrival waits, or RF waits can be symptoms of slow remote send/receive; trace the upstream sender and downstream receiver before blaming local compute.
- If only max is high, report channel, receiver, or BE skew/outlier rather than generic cluster-wide network slowness.
- When RPC or remote-transfer evidence is large, do not demote it below speculative plan-shape causes unless active operator timers and row amplification clearly dominate the elapsed time.
- A disabled optimization or large shuffle input can explain why many rows are sent, but it does not by itself explain multi-second RPC latency. If RPC time is the elapsed-time limiter, call the plan/data volume an amplifier and keep BE-to-BE transfer/receiver outlier in the main conclusion.
- Use a dominance check before naming plan shape as root: compare RPC time to query elapsed, `SerializeBatchTime`, `CompressTime`, `LocalSendTime`, scan CPU, sort/window CPU, and downstream active timers. If RPC dominates and bytes/RPC count are meaningful, conclude likely RPC path or receiver/BE outlier and request per-channel/target-BE throughput evidence.
- Do not let a tempting SQL optimization, such as disabled partition TopN, outrank RPC evidence when send RPC or sink finish latency is the elapsed-time limiter and local sort/window active timers are much smaller. State that the SQL shape explains volume, while abnormal RPC/BE-to-BE transfer explains latency.
- If `DATA_STREAM_SINK_OPERATOR` sends only tens of MB per channel but `RpcAvgTime` is near seconds, `RpcMaxTime` is several seconds, `LocalSendTime` and serialization/compression are milliseconds, conclude abnormal BE-to-BE RPC/transfer or receiver-BE outlier. SQL shape, disabled TopN, or row count should be framed as the volume amplifier, not the latency root. Name the target host/channel if the profile exposes one, and ask for BE-to-BE throughput or monitoring as validation.
- In memory-resource cases, run the memory pass before this RPC rule. Low memory percentage, low query memory limit, spill pressure, or reservation waits can make exchange buffers wait for downstream progress. In that pattern, RPC/buffer waits are symptoms unless per-channel transfer remains abnormal after memory pressure is removed.

## Sort, TopN, Spill, And Memory

When sort, TopN, spill, or memory limits appear:

- Distinguish full sort from TopN, two-phase TopN fetch, late materialization, and result-sink/client waits.
- If spill appears, report memory/config pressure separately from exchange waits.
- For ORDER BY LIMIT timeouts, inspect TopN optimization markers and second-phase row-id fetch/RPC evidence before dismissing sort. If `TOPN OPT` / `OPT TWO PHASE` appears together with a long result-sink or lifecycle stall and zero/tiny scan/sort rows, list delayed materialization, row-id fetch target BE, resource tag, and BE log checks before concluding generic client/result return latency.
- For OOM or `MEM_LIMIT_EXCEEDED`, do not stop at the largest row-count operator. Determine the memory owner: join build hash table, join probe/intermediate blocks, aggregation hash/state arenas, ordered aggregate states, sort buffers, table-sink buffers, exchange buffers, or expression materialization.
- If `group_concat`, `array_agg`, ordered aggregate, distinct aggregate, or high-cardinality grouping appears near the memory peak, evaluate aggregate-state cardinality and aggregation phase placement before concluding join intermediate explosion. A large join may feed the problem, but the OOM root can be map-side aggregate state creation.
- If non-default memory settings are visible, such as a very low memory percentage or query memory limit, treat them as root-cause candidates before network/RPC or join-order explanations.
- If non-default parallelism settings are visible, such as disabled parallel scan or `parallel_pipeline_task_num=1`, treat poor resource utilization as a root-cause candidate before optimizer/join-order speculation.

## Expression, UDF, And Projection Hotspots

High `ProjectionTime`, expression timers, or UDF counters are direct CPU evidence, but still check why they are amplified:

- Upstream join/aggregation may create too many rows before the expression.
- `GLOBAL LIMIT`/`GATHER` or fragment `instance_num=1` can serialize otherwise parallel expression work.
- String, JSON/VARIANT, encryption/decryption, split, regexp, and user UDFs often need function-specific evidence and row-count/skew comparison.
- If the SQL contains `SPLIT_BY_STRING`, large field-length variance, or repeated string normalization functions, inspect expression/projection time and per-instance skew before attributing the profile only to scan/shuffle/write volume.
- If the direct hotspot is a UDF/projection downstream of `GLOBAL LIMIT`, `GATHER`, or `instance_num=1`, treat accidental serialization as a root-cause candidate, not just a follow-up check.
- Expression CPU is not always exposed as `ProjectionTime`; it may be accounted inside join probe/output, SELECT, scan materialization, sink expression, or table-sink write paths. For massive-row string functions such as `SPLIT_BY_STRING`, regexp, trim/replace chains, or `COUNT`-like string splits, do not require visible `ProjectionTime` before promoting expression cost.
- When `HASH_JOIN_OPERATOR` probe/output, `OtherJoinConjunct`, or projection CPU dominates, inspect the SQL/plan expression text for residual string-normalization chains such as `INSTR`, `COALESCE`, `NULLIF`, `TRIM`, and `REPLACE`. Name the expression family as the likely root when it matches the hot operator.
- A large `LIMIT N` can still force `GLOBAL LIMIT`/`GATHER` and serialize downstream work even when it is not selective. If a hot UDF/projection runs with `instance_num=1` downstream of `LIMIT`/`GATHER`, call accidental serialization the root amplifier and the UDF/expression the direct CPU bottleneck.
- For full-volume INSERT/SELECT, a visible `SPLIT_BY_STRING` or `cardinality(split_by_string(...))` over string columns is a stronger root-cause candidate than generic scan/shuffle/write volume. If per-instance progress is uneven or one host/channel is long-tailed, conclude string split cost and input-length skew unless active sink/write timers clearly dominate independently.
- For `SPLIT_BY_STRING` used only to count delimiters, suggest the validation/repair family as `COUNT_SUBSTRINGS` or `length - length(replace(...))`. This is not generic tuning advice: it is the expected evidence check when split materializes arrays only to count elements.
- In paired-profile tasks, this expression rule must be checked after resource/layout diffs. If the faster profile mainly changes `parallel_pipeline_task_num`, `instance_num`, tablet balance, local shuffle, or target distribution while the expression text stays the same, make the resource/layout difference the root layer and expression cost the amplified direct work.

## External Scans, Catalogs, And Metadata

For JDBC, Paimon, Hive/Iceberg, catalog, and metadata profiles:

- Report the remote or connector path as the profile-visible bottleneck.
- List version, driver/JDK, catalog refresh/cache, native versus JNI scan, delete-file/DV read time, file count, and remote filesystem checks as missing evidence when absent.
- Do not infer a Doris CPU root cause from a connector scan profile without remote/driver/version evidence.

## Lifecycle, Cache, And Background Work

If FE plan/schedule time, wait/fetch result time, result sink waits, or worker waits dominate:

- Keep them separate from BE operator active work.
- Check for SQL/result cache locks, cache warmup/freshness fallback, background load/warmup jobs, heavy metadata serialization, FE rewrite/analyze hotspots, and worker-thread starvation evidence.
- For FE/JVM pressure during `INSERT`, check whether the SQL is large `INSERT INTO VALUES`, whether data size or column count is high, and whether traffic/frequency explains GC. Do not stop at generic Nereids rewrite/CTE speculation.
- Long LocalExchange/LocalExchangeSink dependency waits with little scan/sort CPU usually indicate local shuffle/channel imbalance or a local-shuffle implementation issue, not client result-fetch slowness.
- If only profile lifecycle counters are available, report the stall as proven but keep the deeper cache/log/background-job cause as a next check.

## Storage IO, Cache, MOR, And Delete Files

When scan IO or cache counters dominate:

- Separate physical IO (`IOTimer`, file read/open, decompression), lazy read/materialization, FileCache lookup/fill, page-cache warmup, MOR merge, and Paimon/Iceberg delete-file work.
- Use bytes, rows, file/split counts, delete-file timers, and cache hit/miss counters to avoid collapsing all storage symptoms into generic scan volume.
- High `LazyReadTime`, random row-id fetches, or many small block reads can mean random IO or disk/cache capacity pressure even if total scanned bytes look moderate.
- If remote IO/FileCache dominates and repeated runs differ, check local cache capacity, eviction, compaction/small-file shape, and warmup state before concluding ordinary cold scan.
- If lazy read, block load, row-id/deferred materialization, or many small block reads dominate a scan, do not explain the slowdown only as "full scan volume". Prefer random IO/lazy materialization or disk/cache medium pressure, then ask whether scanner-count changes or storage medium evidence confirm it.
- If scan time is remote-IO/FileCache dominated with low CPU, inspect FileCache hit/miss/fill counters, read-write separation context, small-file/compaction evidence, and cold-vs-warm profiles. When those signals are present, root cause is cache miss/read-write separation/warmup state rather than predicate/index CPU.
- With paired cold/warm or slow/fast internal OLAP profiles where CPU is low and the delta is storage/FileCache/delete-bitmap/rowset initialization, make cache-miss or read-write-separation warmup state the likely issue-level root if the profile names FileCache/remote IO. High compaction score or small files are validation evidence, not a separate generic scan-volume conclusion.

## Paired Profiles And Differential Evidence

When the task provides slow/fast, old/new, internal/external, or rewritten profiles:

- Build a compact diff across join order, scan rows, pruning, `instance_num`, intermediate rows, exchange distribution, and sink layout.
- Treat the fast profile as counterfactual evidence. If it removes the slow bottleneck through join/pruning/parallelism/distribution changes, make that difference the root cause layer.
- Do not keep join order, statistics, partition pruning, or parallelism as vague uncertainty when the paired profile directly exposes the difference.
- Paired profile differences override local wait-counter temptations. If the slow profile has large RPC/scanner/exchange waits but the paired fast profile changes join order, pruning, `instance_num`, or distribution and removes the wait chain, diagnose the plan/data-layout difference as root and the wait as a symptom.
- If only one profile is provided, keep the deeper cause as likely and list the paired profile, DDL, stats, hint, or rewrite check needed to prove it.
