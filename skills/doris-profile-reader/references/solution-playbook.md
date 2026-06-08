# Doris Performance Solution Playbook

Use this file only after the root-cause layer is identified. Its purpose is to produce high-quality solution fields without turning every profile observation into generic tuning advice.

## 1. Choose The Solution Source

Before writing `historical_solution`, classify the action source:

1. `profile_proven`: the provided profiles directly show a before/after or a setting/rewrite effect. Name the exact change and the observed profile delta.
2. `historical_pattern`: the root-cause layer matches a pattern in `known-issues-solutions.md`. Preserve the exact recorded parameter, value, PR, version, SQL rewrite shape, or operational action when present.
3. `needs_validation`: Doris code or the profile suggests a plausible knob or rewrite, but the materials do not prove it solved this historical issue. Put it in `next_checks`, not in `historical_solution`.
4. `no_historical_solution`: the profile proves a bottleneck but not a supported fix. Leave `historical_solution` and `solution_evidence` empty; explain the missing evidence in `no_solution_reason`.

Do not mix these tiers. A historical solution should be short and specific; validation checks can be broader.

For output schemas with both `historical_solution` and `next_checks`, enforce this boundary strictly:

- If the action source is `needs_validation`, leave `historical_solution` and `solution_evidence` empty and put the action in `next_checks`.
- If the action is a DDL/layout rewrite, cache/index knob, join hint, RF wait change, memory setting, or SQL rewrite inferred only from a similar-looking bottleneck, it is `needs_validation`, not `historical_pattern`.
- A concrete fix is allowed only when the provided profiles prove the before/after effect, or `known-issues-solutions.md` records the exact action for the matched mechanism.
- If the historical record says there was no explicit mitigation, or only records a diagnosis/monitoring follow-up, do not fill a solution from a nearby pattern family.
- Treat the issue-id examples in `known-issues-solutions.md` as positive anchors, not broad permissions. If the current issue is not one of the listed examples for that action and the provided profile does not prove the same action by before/after evidence, do not transfer the action into `historical_solution`; keep it as a possible `next_check`.

## 2. Map Root Cause To Action Type

Use the narrowest action family that matches the root cause:

- Planner/statistics/join order: `ANALYZE` or script-based stats collection only when stale/missing stats are the recorded cause; `disable_join_reorder`, `leading`, `shuffle`, or `broadcast` hints only when the profile proves a bad join order/distribution or the historical record names that workaround; SQL rewrite when the recorded fix changes join order, removes unused joins, splits `OR`, pre-aggregates/deduplicates a dimension, or changes the probe/build side.
- Runtime filter: `runtime_filter_wait_time_ms` only when scans start before useful filters arrive or the historical record gives a value such as 2000/5000/10000. Same-SQL slow/fast profiles where the slow one starts without a useful RF and the fast one waits long enough for it are RF-wait evidence; do not convert that pattern into generic join-order hints. `enable_runtime_filter_prune=false` is a different action for bad RF partition pruning; do not replace it with longer RF wait. If RF is already ready within the configured wait, do not recommend increasing wait unless the historical record explicitly did.
- Parallelism/local shuffle/scan: tune `parallel_pipeline_task_num`, `parallel_fragment_exec_instance_num`, `enable_parallel_scan`, `enable_local_shuffle`, or `force_to_local_shuffle` only when the issue is under-parallelism, local-shuffle skew, gather/global-singleton behavior, or session/global scope. Preserve scope: session-only extraction settings are not global cluster fixes.
- Bucket/tablet/layout: rebucket, change bucket key/count, or redesign target write buckets only when the current issue is explicitly anchored to a recorded layout mitigation in `known-issues-solutions.md`, or the provided profiles directly prove a layout A/B effect. Do not use this for ordinary storage IO, expression CPU, comparison-only scanner-count differences, or point queries that merely open many tablets.
- Bucket/tablet/layout actions require profile-proven or historical before/after evidence. If the profile only shows many tablets, scanner wait, or a tiny result after a large scan, put DDL/bucket changes in `next_checks` unless the known history records that they fixed this mechanism.
- Index/search: add a non-tokenized inverted index, add an `IN` filter, or rewrite to `search()` only when predicate/index evidence matches the exact historical mechanism. Doris `search()` is only supported in WHERE filters directly on a single-table OLAP scan; do not suggest it for projections, joins, GROUP BY, generic multi-table expressions, or ordinary expression/filter CPU without a recorded search-index-skip fix.
- Expression/projection: rewrite repeated CASE/COALESCE/string chains, enable common subexpression only when expression CPU is the root; for delimiter counting, prefer `COUNT_SUBSTRINGS` or `length - length(replace(...))` over materializing arrays with `split_by_string`.
- TopN/sort/lazy materialization: distinguish full sort that cannot use TopN from TopN two-phase/lazy-materialization regressions. `full_sort_max_buffered_bytes` and `topn_lazy_materialization_threshold=0` solve different patterns.
- Memory/spill/OOM: identify the owner first. Low workload-group `max_memory_percent` or query memory limit means change the memory/resource-group setting. Aggregate-state OOM may need a plan/code fix such as one-stage aggregation. Spill knobs are stage-specific (`spill_join_build_sink_mem_limit_bytes`, `spill_aggregation_sink_mem_limit_bytes`, `spill_sort_sink_mem_limit_bytes`, `spill_sort_merge_mem_limit_bytes`); do not present generic "increase memory/spill" as a solution.
- Storage/cache/index IO: choose between compaction, cache warmup/freshness fallback, inverted-index cache/fd tuning, BKD/remote-IO instrumentation, specific PR/upgrade, or external storage optimization. These are not interchangeable.
- For storage/index/cache symptoms, a cold cache, inverted-index wait, scanner fanout, or high IO counter is not by itself a mitigation. Cache-size, fd-limit, compaction, rebucketing, JNI/native scan, and instrumentation PRs are separate historical actions; use only the one explicitly recorded for the matched path.
- Client/result/metadata/FE lifecycle: use Arrow Flight/reduced result size, avoid repeated catalog refresh, close/limit profile retention, reduce excessive temporary tables, or upgrade specific fixes only when that lifecycle layer is the root.
- RPC/exchange: if `DATA_STREAM_SINK_OPERATOR` RPC dominates, locate receiver/network outliers only when the history or per-channel evidence supports it. If the historical fix is SQL rewrite to reduce exchange input, state the rewrite instead of inventing a network repair.

## 3. Preserve Exact Historical Details

When `known-issues-solutions.md` contains exact details, keep them in `historical_solution`:

- parameter names: `disable_join_reorder`, `enable_runtime_filter_prune`, `runtime_filter_wait_time_ms`, `parallel_pipeline_task_num`, `enable_adaptive_pipeline_task_serial_read_on_limit`, `topn_lazy_materialization_threshold`, `full_sort_max_buffered_bytes`, `max_scan_key_num`
- parameter values: examples include `runtime_filter_wait_time_ms=5000`, `runtime_filter_wait_time_ms=10000`, `parallel_pipeline_task_num=3/8`, `topn_lazy_materialization_threshold=0`, `full_sort_max_buffered_bytes=268435456`, `max_scan_key_num=100`
- PR or version anchors: if the historical record names a PR/version, include it instead of a vague "upgrade"
- SQL shape: "split OR into UNION", "deduplicate/pre-aggregate dimension", "make table X the probe side", "remove unused LEFT JOINs", "MV pre-aggregation", or "avoid randomized SQL rewrites so sql_cache hits"
- operational action: "manual compaction after Stream Load", "drop alias function", "remove slow node", "restore global parallelism default but keep session override"

If you cannot preserve the exact detail because the profile does not match the pattern, do not give that solution.

## 4. Avoid Over-Inventing

Common mistakes:

- Replacing a recorded PR/version fix with generic hints or stats collection.
- Replacing a recorded parameter with a related but different one, e.g. recommending RF wait when the fix was disabling RF pruning.
- Recommending `search()` for any slow text predicate even though code restricts it to single-table OLAP-scan WHERE filters.
- Treating "check DDL", "collect stats", "try a hint", "inspect receiver BE", "compare rerun", or "verify memory setting" as historical solutions. These are `next_checks` unless the historical record says that action fixed or mitigated the issue.
- Adding a second speculative mitigation after the recorded solution. If the history says `set topn_lazy_materialization_threshold=0`, do not also suggest bucket redesign.
- Applying a known action to an unlisted issue by family resemblance alone, for example RF-wait tuning for any late RF symptom, rebucketing for any scan fanout, compaction strategy for any open/init cost, or search/cache tuning for any expression/index wait. These are useful checks, not historical solutions.
- Treating a partial profile, cached plan, commented-out SQL variant, async-profiler flamegraph, or plan-only artifact as negative proof against a recorded Jira A/B result. If history says a hint, setting, PR, or workaround changed runtime by orders of magnitude, preserve that history and state that the current artifact may be a variant or incomplete for solution selection.
- Mapping every bad join-side or OOM symptom to join hints. If the recorded fix is a stats/code PR, row-count/null handling fix, memory limit fix, or aggregation-shape fix, state that exact fix instead of hints.

## 5. Output Field Rules

- `historical_solution`: one concise sentence naming the supported action. If historical details exist, include them.
- `solution_confidence`: use `historical_pattern` for known issue patterns, `profile_proven` for paired-profile proof, `needs_validation` only when the schema requires a non-empty likely action but it is not historically proven, and `no_historical_solution` when leaving the solution empty.
- `solution_evidence`: cite the matched pattern name and the exact profile signal, not just the issue id.
- `no_solution_reason`: say what is missing, such as "profile shows scan fanout, but no DDL or historical pattern proves rebucketing fixed this case."
- `next_checks`: put validation work here. Keep it minimal and ordered by the evidence needed to choose a safe fix.
