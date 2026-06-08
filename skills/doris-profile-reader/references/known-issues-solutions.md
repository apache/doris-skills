# Known Issues And Historical Mitigations

Use this file only after the profile root cause has been identified. It maps recurring Doris profile-visible causes to mitigations that were explicitly recorded in historical Jira-derived conclusions. Do not invent a fix from analogy. If the profile does not match one of these patterns, say that no historical profile-proven solution is available and list the smallest validation check.

The issue ids are evidence anchors from the local profile issue inventory. They are not a complete product runbook.

## Planner, Join Order, And Runtime Filter

- Large `IN` predicates make Nereids predicate inference or range simplification dominate planning: historical mitigation was disabling `INFER_PREDICATES`; the durable fix limited IN option handling. Examples: `CIR-15000`.
- `AND/OR` or compound equality filters cannot use indexes effectively: recorded short-term mitigations include adding non-tokenized inverted indexes on equality columns or adding explicit `IN` filters; long-term fixes include `OrToIn` work such as PR #46468. Examples: `CIR-15082`.
- High-expansion dimension joins where optimizer already placed the join late: recorded mitigation was deduplicating on the import side or pre-aggregating the dimension, not join hints. Examples: `CIR-15287`.
- Bad join order or wrong broadcast/shuffle choice from bad stats, skew, or wide-column undercosting: historical mitigations include `disable_join_reorder=true`, leading/shuffle/broadcast hints, or rewriting SQL to put the selective/probe side earlier. Keep exact recorded variants: `disable_join_reorder=true` plus SQL adjustment (`CIR-15292`), `enable_bucket_shuffle_join=false` to avoid a bad bucket-shuffle plan (`CIR-17395`), `disable_join_reorder` hint for stats-driven join-order regression (`CIR-19881`), make `tbl_bke_ncard_dtl` the probe side and test real placeholder values (`CIR-19962`). Examples: `CIR-15106`, `CIR-15292`, `CIR-15421`, `CIR-17395`, `CIR-17694`, `CIR-18674`, `CIR-19881`, `CIR-19962`, `CIR-20175`.
- Wrong row-count/null/hot-value estimation with a recorded code fix should not be replaced by hints. Examples: num-null Normalize fix PR #49891 (`CIR-15403`); missing hot-value/full stats where `disable_join_reorder` changed 13s to milliseconds (`CIR-19881`).
- For the stats/hot-value issue anchored by `CIR-19881`, the recorded mitigation is the `disable_join_reorder` hint/setting evidence plus fixing the stats/hot-value collection gap. Do not replace it with SQL-cache stabilization even if a provided profile variant has `Is Cached` differences or commented-out joins.
- Runtime filters arrive too late or do not wait long enough before scan: preserve exact values when recorded. Examples: auto stats plus `runtime_filter_wait_time_ms=5000` (`CIR-15309`), raising default 1s wait to 2s for same-SQL jitter where the slow query missed RF (`CIR-17800`), `runtime_filter_wait_time_ms=10000` reducing scan time (`CIR-15321`, `CIR-18681`), raise RF wait and also inspect scanner thread pool / reduce scanner count (`CIR-19307`).
- Runtime-filter partition pruning can be the problem itself: recorded mitigation was disabling `enable_runtime_filter_prune` at SQL scope, not increasing RF wait. Examples: `CIR-15406`.
- SQL cache/parser/rewrite regressions: recorded mitigations include avoiding randomized SQL rewrites so SQL cache can hit, disabling `REWRITE_PROJECT_EXPRESSION`, or upgrading parser optimizations. Examples: `CIR-16304`.
- Statistics collection as the actual mitigation: when auto stats are blocked or absent, recorded mitigations include manual/scripted stats collection or waiting for stats collection before UPDATE. Examples: `CIR-16359`, `CIR-18601`.
- OR rewritten as mark join or full-scan-like plan: recorded mitigation was splitting `OR` into `UNION` or otherwise rewriting the SQL so pruning/filtering can apply. Examples: `CIR-20080`.
- Bitmap union aggregation where scan filtering still keeps nearly all rows: recorded mitigation was MV pre-aggregation because bitmap union itself had no further runtime optimization. Examples: `CIR-20062`.
- Complex Cascades/join-reorder planning dominates FE time: historical mitigations include disabling selected rewrite/join rules or enabling DPHyp where appropriate. Examples: `CIR-15817`, `CIR-19809`.
- Materialized-view rewrite dominates FE planning time: historical mitigations include disabling `enable_materialized_view_rewrite` for the query/workload or upgrading to a version with the relevant rewrite fix such as apache/doris#59972. Examples: `CIR-19116`, `CIR-20096`.
- New optimizer or row-store path regression with point-query IO: recorded mitigation was temporarily disabling the new optimizer / using the row-store path and backporting PR #47661 or using fixed versions. Examples: `CIR-20014`.
- If a current profile variant lacks the original join operators but Jira/history records an A/B hint or setting that changed latency by orders of magnitude, do not use the variant alone to erase the historical solution. Preserve the recorded mitigation and mark the artifact mismatch in `uncertainty`. Examples: `disable_join_reorder` hint for the statistics/hot-value issue (`CIR-19881`).

## Scan Pruning, Bucket Layout, And Parallelism

- Point or narrow queries open many buckets/tablets because predicates do not include the bucket key: historical mitigation is changing table distribution or query predicates so bucket/tablet pruning can apply; for small tables, rebuilding to a single tablet/BE layout was used. Examples: `CIR-20281`, `CIR-20135`.
- Do not apply bucket/tablet redesign to every point or narrow query that opens many tablets. If the issue record only explains a comparison, concurrency difference, scanner count, storage state, or data distribution but does not record a DDL/layout mitigation, leave `historical_solution` empty and put DDL checks in `next_checks`.
- A point query with many tablets/scanners is a diagnosis pattern, not a solution pattern. Unless the current issue matches a listed layout-mitigation anchor such as `CIR-20281`/`CIR-20135` or has a profile-proven layout A/B, do not write rebucketing, changing distribution keys, or rebuilding tablets into `historical_solution`.
- RANDOM buckets or bucket keys mismatch query predicates, so indexes filter rows but cannot avoid tablet/segment fanout: historical mitigation is rebucketing with a high-cardinality key aligned with query predicates. Examples: `CIR-20408`, `CIR-20236`.
- Low tablet count or local shuffle disabled caps scan/aggregation parallelism: historical mitigations include enabling local shuffle/parallel scan or increasing bucket/tablet count when the table layout is the limiting factor. Examples: `CIR-15370`, `CIR-18488`.
- Local shuffle or parallelism implementation/version issues: recorded mitigation may be "upgrade to the fixed version" rather than changing table layout. Examples: local-shuffle issue fixed in later version (`CIR-15734`), gather `instance_num=1` fix distinguishing user-set 1 from real global 1 (`CIR-19329`).
- Query/session parallelism too low: preserve exact scope and value when recorded. Examples: `parallel_pipeline_task_num=8` satisfied performance (`CIR-18405`), `parallel_pipeline_task_num=3` plus later SQL rewrite to full scan then GROUP BY (`CIR-18738`), keep extraction-session parallelism at 2 but restore global/default parallelism to 0/16 (`CIR-19817`), restore `enable_parallel_scan` and `parallel_pipeline_task_num` defaults when disabled (`CIR-18327`).
- Scan distribution skew makes one aggregation/join instance dominate: historical mitigations include `force_to_local_shuffle`, changing bucket key, changing join distribution with hints, or fixing skewed pressure-test/query conditions. Examples: `CIR-19907`, `CIR-19910`, `CIR-17351`, `CIR-17865`, `CIR-18792`.
- `max_scan_key_num` prevents prefix-key range pruning for long `IN` lists: historical mitigation was increasing `max_scan_key_num=100` for that query. Examples: `CIR-15763`.

## Scan Open, Delete Bitmap, File And Cache Paths

- `ScannerInitTime`/`OpenTime` dominates count or scan with little CPU/IO because delete bitmap or rowset metadata work is excessive: historical mitigation was changing compaction strategy and disabling time-series compaction for affected unique-key layouts. Examples: `CIR-15305`.
- Parallel scan opens many/all segment files and file-open cost dominates: historical mitigation was disabling parallel scan temporarily or picking the relevant fix. Examples: `CIR-15896`, `CIR-19671`.
- FileCache/remote IO dominates with low CPU, especially in read-write separation or freshness fallback: historical mitigations include cache warmup fixes, compaction/small-file checks, and validating read-write separation cache state. Examples: `CIR-16577`, `CIR-19566`.
- Read-write separation freshness fallback after MOW/base compaction: recorded fixes included counting index size in rowset size so warmup wait is not too short, and handling rowsets missing from the state map. Examples: `CIR-19566`.
- Segment cache misses on VARIANT columns repeatedly load footer/segment metadata: historical mitigations included adjusting `estimated_mem_per_column_reader`, disabling `segment_cache_prune`, and increasing segment cache. Examples: `CIR-19450`.
- Inverted index or searcher cache cold/miss dominates point/search queries: historical mitigations include increasing `inverted_index_fd_number_limit_percent` and `inverted_index_searcher_cache_limit`, or upgrading when the issue is an implementation bug. Examples: `CIR-16111`, `CIR-16667`. Do not apply these to BKD remote IO instrumentation or match-regexp prefix-seek fixes.
- If an issue record says index/cache tuning did not mitigate, or the profile only proves an index/searcher wait without a recorded cache-capacity fix, do not invent cache/fd tuning as the solution. Keep it as a validation check.
- Match-regexp or inverted-index implementation fixes: preserve exact fix anchors when recorded, such as match-regexp prefix-seek optimization PR #50968. Examples: `CIR-15911`.
- BKD or index remote IO attribution gaps: recorded follow-up was adding fine-grained Profile/BKD remote IO statistics, such as selectdb-core PR #4020; this is instrumentation/fix work, not cache tuning. Examples: `CIR-16102`.
- High IO that improved after version upgrade: record the version when known, such as upgrade to 3.0.5 reducing slow queries. Examples: `CIR-16263`.
- Tablet placement or creation policy causes unstable scan time: recorded mitigation was disabling `enable_round_robin_create_tablet`, followed by PR #52688. Examples: `CIR-16475`.
- Hive/external partition pruning implementation gaps: recorded mitigation can be an external/Hive-side or Doris-side PR, such as Hive-side PR #55378 and binary-search partition-pruning support for external scans. Examples: `CIR-16813`.
- Paimon/JuiceFS native scan path problems: recorded mitigation was forcing JNI scan when profiles/comments show native scan path failures such as jfs path or "No alive broker". If the provided artifact is not a normal BE runtime profile, do not replace this history with an unrelated FE flamegraph root; state the artifact mismatch and preserve force-JNI as the recorded workaround when the issue/history matches. Examples: `CIR-18734`.
- Stream Load followed by slow queries due to compaction state: recorded mitigations include manual compaction after load and tuning compaction parameters. Examples: `CIR-18937`.
- Iceberg delete-file over-read or lakehouse reader bugs: use the recorded Doris code fix when present, such as PR #62525 to avoid reading delete files unnecessarily. Examples: `CIR-19929`.

## Expression, Projection, And SQL Shape

- CASE WHEN/COALESCE expressions are repeatedly evaluated and dominate CPU: historical mitigations include rewriting CASE WHEN into equivalent OR predicates or enabling common-subexpression elimination when supported. Examples: `CIR-15356`, `CIR-16221`.
- Common subexpression support: when recorded, preserve the exact parameter `enable_common_sub_expression=true`; do not reduce it to vague "CSE". Examples: `CIR-16221`.
- Massive `SPLIT_BY_STRING` or `cardinality(split_by_string(...))` over many rows dominates INSERT/SELECT CPU: historical mitigation was rewriting to `LENGTH - LENGTH(REPLACE)` and later using `COUNT_SUBSTRINGS`. Examples: `CIR-19724`.
- Heavy string residual expressions such as `INSTR`, `COALESCE`, `NULLIF`, `trim`, or `REPLACE` dominate join/projection work: historical mitigation was removing or rewriting that expression segment. Examples: `CIR-19705`.
- Ordinary expressions cannot use search-index skip behavior and scan too much data: historical mitigation was rewriting to the `search()` function. Examples: `CIR-19646`.
- `search()` rewrite is only a solution for the exact search-index-skip pattern. A slow text predicate, residual expression, scan fanout, or filter CPU without that recorded mechanism should leave `historical_solution` empty.
- Full sort cannot use TopN and consumes single-node memory: historical mitigation was rewriting SQL where possible; for specific sort-buffer regressions, increasing `full_sort_max_buffered_bytes` was used. Examples: `CIR-16033`, `CIR-19844`.
- Adaptive serial scan for small LIMIT can be harmful: recorded mitigation was disabling `enable_adaptive_pipeline_task_serial_read_on_limit=false` for validation/workload when that setting serialized the scan. Examples: `CIR-16376`.
- TopN lazy materialization/two-phase read regressions: recorded mitigation may be `topn_lazy_materialization_threshold=0`, not full-sort buffering or bucket layout. Examples: `CIR-19476`.
- Sort-buffer regression: when recorded, preserve exact setting `full_sort_max_buffered_bytes=268435456` and related PR #8213. Examples: `CIR-19844`.
- Expression or function implementation bugs with recorded fixes: use the PR/temporary workaround, not generic hints. Examples: apache/doris#50574 (`CIR-15806`), selectdb-core PR #3976 (`CIR-15910`), temporarily drop alias function with follow-up PR #51619 (`CIR-16413`).
- When a join/OOM symptom is caused by incomplete column statistics from wide-table auto-collection limits or null-count estimation, use the recorded stats/code fix such as apache/doris#50574 (`CIR-15806`). Do not replace it with generic join hints even if the runtime profile shows a bad build side.

## Insert, Sink, And Data Distribution

- INSERT receiver or UNION/local-exchange skew sends almost all rows to one receiver because target bucket/key design mismatches hot values: historical mitigation was redesigning the target bucket key/count and write bucket parallelism. Examples: `CIR-20103`.
- INSERT/CTE/UNION input explodes to tens or hundreds of billions of rows before filtering: historical mitigation was rewriting with semi join or earlier filtering. Examples: `CIR-20166`.
- `insert into values` planning is slow in newer optimizer paths: historical mitigation was using Stream Load or upgrading to a version with the optimizer fix. Examples: `CIR-16099`.
- Aggregation state OOM from ordered `group_concat`/`array_agg` map-side state explosion: recorded mitigation/fix was changing to one-stage aggregation or the corresponding optimizer/code fix, not merely join hints. Examples: `CIR-16884`.

## Exchange, RPC, And Client/Network

- `DATA_STREAM_SINK_OPERATOR` RPC time dominates while local serialize/send timers are small: historical mitigation depends on confirming BE-to-BE network or receiver outlier; do not bury the root behind generic data volume. Examples: `CIR-15966`, `CIR-19234`, `CIR-19692`.
- If the recorded fix for an RPC-heavy profile was SQL rewrite that reduced exchange input, state the SQL rewrite as the solution and keep receiver/network inspection as a next check. Examples: `CIR-19692`.
- Client/result writing dominates despite small BE work: historical mitigation included using Arrow Flight or reducing returned data/query volume. Examples: `CIR-15964`.
- Concurrent query RPC saturates NIC bandwidth: historical mitigation was upgrading network capacity before retesting. Examples: `CIR-18277`.

## External Catalog, Schema Scan, And Version-Specific Fixes

- `SCHEMA_SCAN_OPERATOR`/information_schema waits for minutes with little BE work: historical mitigation was upgrading or applying the specific fix for the schema scan hang. Examples: `CIR-15894`.
- JDBC/Oracle external catalog query slows because of driver-version detection or repeated refresh: historical mitigations included upgrading the fixed version and avoiding unnecessary refresh behavior. Examples: `CIR-15284`, `CIR-15566`.
- Preserve exact external-catalog details when known: Oracle driver version detection fixed in 2.1.7 / PR #41407 and validated after upgrade to 2.1.8.3 (`CIR-15284`); repeated `refresh catalog` on 2.1.7 rebuilt metadata/connections and should be avoided or fixed (`CIR-15566`).
- Hive external dynamic partition pruning does not trigger: historical mitigation was upgrading to a version where `RuntimeFilterPartitionPrunedRangeNum` becomes non-zero for the query. Examples: `CIR-19791`.
- External file/lakehouse IO dominates: historical records usually recommended lakehouse/HDFS/MinIO-side optimization or compaction/partition-pruning checks, not a generic SQL knob. Examples: `CIR-18670`, `CIR-19995`.
- FE profile memo memory growth: recorded mitigation was closing/limiting profile retention and using fixes #57257/#59797/selectdb #5499. Examples: `CIR-19149`.
- Excessive temporary table/table count causing metadata DDL latency: recorded mitigation was deleting/reducing temporary tables; after deleting 70k+ temp tables, create-table slowness stopped. Examples: `CIR-19170`.

## Memory, Spill, And Resource Groups

- Low workload-group memory percentage or query memory limit can make spilled queries timeout or appear exchange-blocked. Recorded mitigation was correcting the too-small memory setting, not join hints or RPC repair. Examples: `CIR-19561`.
- FE/JVM memory pressure from persisted alias function serialization: recorded temporary workaround was dropping the alias function and tracking the code fix PR #51619. Examples: `CIR-16413`.
- Warmup/load event cancellation bugs can leave zombie warmup jobs that repeatedly retry FE requests and affect heavy work threads. Recorded mitigation was applying the code fix PR #62805, not generic RPC/result-chain tuning. Examples: `CIR-20058`.

## How To State A Solution

- Separate `root_cause` from `historical_solution`. The solution should be conditional: "For this historical pattern, recorded mitigations were ...".
- Do not present a parameter as universally safe. Name the matching profile signal and the issue examples.
- If the profile lacks the schema/config/version evidence needed to select a solution, say "profile supports this cause; solution requires checking X" rather than guessing.
- Do not fill `historical_solution` with validation work. "Check DDL", "inspect receiver BE", "collect stats", "try a hint", "verify memory setting", or "compare a rerun" are `next_checks` unless a historical record explicitly says that action solved or mitigated the issue.
- If the known historical pattern does not match the current profile, do not force it by issue id or by a vague family resemblance. Leave `historical_solution` empty and explain the mismatch in `no_solution_reason`.
