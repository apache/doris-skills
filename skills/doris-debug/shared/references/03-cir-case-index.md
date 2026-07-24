# Doris Production Case Index

> 45 representative cases selected from 20,000+ production troubleshooting records, organized by doris-debug skill domain.
> Each case includes Symptom / Root cause / Fix / Key diagnostic actions.

## Statistics Overview

| Diagnostic Domain | Cases | Key Patterns |
|--------|--------|----------|
| Query | 7 | Plan Time / Scan bottleneck / Exchange E11 / Fluctuating results / Overwrite conflict / Abnormal CPU / Compute group divergence |
| Import | 6 | 307 redirect / FE OOM leak / Slow S3 load / RPC timeout / Arrow format / Slow meta-service |
| Compaction | 5 | Residual SC base score / cumu segfault / Versions compacted / High cumu score / Inverted index rebuild |
| Node | 7 | Auto analyze OOM / file_cache leak / BE coredump / FE bdbje corruption / Persistent BE memory leak / Abnormal CPU / 200GB at startup |
| Tablet | 3 | Abnormal statistics / S3 hot-cold tiering / Write timeout |
| Deployment | 2 | FE NPE at startup / BE fails to start due to config |
| Data Lake | 5 | Glue pagination / Iceberg partitioned table / Plan Time Iceberg / Missing predicate pushdown / View struct |
| Resource Isolation | 5 | Spill disk / cgroup memory / Workload policy CME / Compute group divergence / WG binding |
| Cloud | 5 | Plan race / BE resources not released / Warmup cache miss / File cache memory leak / FDB backlog |

---

## Query — 7 cases

### Case Q1: FE Nereids Plan Time 10min (Iceberg External Table RPC Explosion)

- **Severity**: Medium
- **Doris version**: 4.1.3
- **Symptom**: Total query time 10min8s, `Plan Time=10min8sec`, while actual BE execution is only 214ms over 1MB of data
- **Root cause**: In the Nereids `Finalize Scan Node → Create Scan Range` phase, each `getManifestFiles` call triggers `UpdateRunningStatus`, which issues an `msClient.updateInstance` RPC; 64 files × 63 partitions called repeatedly at ~200ms each → 10min+
- **Fix**: Short term: increase `iceberg_manifest_cache_refresh_interval_s`; long term: improve scan range creation to reduce duplicate RPCs
- **Evidence**: Profile `Create Scan Range Time=10min1sec`, `Get Splits Time=6sec`, `Is Nereids=Yes`
- **Key diagnostic actions**: Profile → Plan Time share → break down Nereids Translate / Finalize Scan Node / Create Scan Range

### Case Q2: CPU Usage Spike (Inverted Index Rebuild)

- **Severity**: Medium
- **Doris version**: 2.1→3.0 upgrade
- **Symptom**: All BEs at 100% CPU with no queries and no loads running
- **Root cause**: After upgrading from Doris 2.1 to 3.0, the compound inverted index format is incompatible, so BEs rebuild indexes for all tablets at startup
- **Fix**: New version skips rebuilding incompatible compound indexes; temporary workaround `SET disable_auto_compaction = true`
- **Evidence**: be/log `begin to write inverted index`, CPU profile `FSWriteTime + CompressTime > 80%`
- **Key diagnostic actions**: `top -H` → be/log `inverted index` → `SHOW PROC '/backends'` CompactionScore

### Case Q3: [E11] Resource temporarily unavailable (Exchange brpc fanout)

- **Severity**: High
- **Doris version**: 4.0.7
- **Symptom**: During peak hours queries fail with `failed to send brpc when exchange, error=[E11]Resource temporarily unavailable`
- **Root cause**: With `parallel_exchange_instance_num=100`, under high concurrency / high fanout queries the exchange RPC sender hits EAGAIN because the brpc socket send queue is full
- **Fix**: Reduce `parallel_exchange_instance_num`; long term backport apache/doris PR #50113 (one rpc send multi blocks)
- **Evidence**: be/log `RPC meet failed: [E11]`, `failed to send brpc when exchange @<target-be>:8060`
- **Key diagnostic actions**: 1) Distinguish E11 brpc from pthread_create EAGAIN (only the latter means the thread pool is exhausted) 2) Count the distribution of target BEs (single node vs whole cluster) 3) Confirm the `parallel_exchange_instance_num` setting

### Case Q4: Same Query Has Very Different Latency Across Compute Groups (Scan Open/Init Phase)

- **Severity**: Medium
- **Doris version**: 4.0.8
- **Symptom**: Same SQL takes 284ms on the fast group but 3sec257ms on the slow group, with identical rows/bytes on both sides (both return 0 rows)
- **Root cause**: On the slow compute group the OLAP scan has `OpenTime=2sec647ms`; before actually reading data it must sync more remote rowset metadata / delete bitmaps (cloud-mode sync overhead)
- **Evidence**: Slow Profile `ScannerInitTime=2sec647ms`, fast Profile `ScannerInitTime=<1ms`
- **Key diagnostic actions**: 1) Compare the scan open/init phases in the Profiles 2) Confirm the ScannerInitTime/OpenTime difference 3) Check compute group cache state

### Case Q5: Overwrite Fails with Partition Conflict

- **Severity**: High
- **Doris version**: 4.0.4
- **Symptom**: INSERT OVERWRITE t PARTITION(p1) SELECT ... WHERE p2=... → "partitions conflict"
- **Root cause**: The PARTITION clause selects p1 but the WHERE condition matches p2; the code did not unify the partition source
- **Fix**: Unify the partition source (use only the PARTITION clause or only the WHERE condition); fixed in 4.0.5+
- **Key diagnostic actions**: EXPLAIN to confirm the actual scanned/written partitions → compare PARTITION clause vs WHERE condition

### Case Q6: Query Results Fluctuate Across Runs

- **Severity**: Medium
- **Doris version**: 2.1.7
- **Symptom**: The same query returns different results across executions
- **Root cause**: Tablet statistics are incorrect, so the CBO picks different scan paths between executions
- **Key diagnostic actions**: Compare the two plans with EXPLAIN → `ADMIN CHECK TABLET`

### Case Q7: Match Phrase vs Like Return Inconsistent Results

- **Severity**: Medium
- **Doris version**: 2.1.12
- **Symptom**: `MATCH_PHRASE_PREFIX('xx')` and `LIKE 'xx%'` return different results on the same data
- **Root cause**: Semantic difference between the Inverted Index tokenizer and LIKE character matching
- **Key diagnostic actions**: 1) EXPLAIN to confirm whether the inverted index is hit 2) `SHOW INDEX` to confirm the index definition

---

## Import — 6 cases

### Case I1: Stream Load HTTP 307 Redirect Failure

- **Severity**: High
- **Doris version**: 4.0.8
- **Symptom**: Stream Load returns 307, but the BE IP in the Location header is unreachable from the client
- **Root cause**: FE redirects to a BE internal IP while the client is on an external network
- **Fix**: `enable_redirect_strict_check = false` + ensure the BE IP is reachable from the client
- **Key diagnostic actions**: `curl -v` to inspect the 307 Location → verify IP reachability → `SHOW BACKENDS`

### Case I2: INSERT INTO Jobs Not Cleaned Up → FE OOM

- **Severity**: Critical
- **Doris version**: 26.0.3
- **Symptom**: FE memory grows continuously until OOM; after restart, reloading historical INSERT jobs causes OOM again
- **Root cause**: After an INSERT INTO job is marked FINISHED, `JobManager` does not clean it up, accumulating thousands of jobs
- **Fix**: Improve job cleanup in FE code; temporarily use `jmap -histo` to confirm InsertJob accumulation
- **Key diagnostic actions**: `SHOW LOAD` / `SHOW INSERT` → `jmap -histo` → `jmap -dump:live`

### Case I3: Broker Load S3 list Is Slow

- **Severity**: High
- **Doris version**: 26.0.3
- **Symptom**: Broker Load from S3 takes far longer than expected; list operations take longer than the download itself
- **Root cause**: Too many files under the S3 prefix + `s3_max_connections` too small
- **Fix**: Increase `s3_max_connections`; merge small files before loading
- **Key diagnostic actions**: S3 list latency → BE log s3 → `s3_max_connections`

### Case I4: Load RPC Timed Out (Heavy Work Pool Saturated)

- **Severity**: Critical
- **Doris version**: 4.0.9
- **Symptom**: During the open tablet writer phase, the load waits more than 60s for the target BE to return the RPC, after which the coordinator cancels the entire load
- **Root cause**: The target BE's `brpc_heavy` work pool was saturated/stuck during that window; `tablet_writer_open` entered the heavy pool but executed too slowly or timed out in the queue
- **Code path**: `VNodeChannel::_open_internal` → `PBackendService_Stub::tablet_writer_open(timeout=60s)` → `PInternalService::tablet_writer_open` → `_heavy_work_pool.try_offer`
- **Fix**: Short term: reduce/stagger load concurrency; mid term: `brpc_heavy_work_pool_threads 256→384`; capture pstack before restarting during an incident
- **Key diagnostic actions**: 1) be/log `RPC call is timed out` on the target BE 2) Confirm whether timeouts cluster in the same window 3) Check for the `fail to offer request to the work pool` signature 4) pstack the stuck point

### Case I5: Arrow Format Stream Load Error

- **Severity**: Critical
- **Doris version**: 2.1+
- **Symptom**: Arrow-format Stream Load fails with a schema parsing error
- **Root cause**: The Arrow IPC format's field type mapping is inconsistent with the Arrow schema Doris expects
- **Key diagnostic actions**: Validate the Arrow schema → BE log arrow → compare against the supported Arrow type mapping

### Case I6: Meta-service Causes Slow Loads

- **Severity**: High
- **Doris version**: cloud 4.0+
- **Symptom**: Load latency grows significantly, disproportionate to data volume
- **Root cause**: Meta-service latency is high during the load publish phase
- **Key diagnostic actions**: Publish-phase latency in fe.log → meta-service latency monitoring

---

## Compaction — 5 cases

### Case C1: Residual Schema Change → High Base Score

- **Severity**: Medium
- **Doris version**: cloud 4.0+
- **Symptom**: Base compaction score max 1490 / avg 1370, while cumu score is normal (max 79)
- **Root cause**: SC operations create many base compaction tablets but do not clean up the SC context; `tablet_state` or SC state blocks execution
- **Evidence**: `get_topn_compaction_score ... type=1` → high score, but `type=2` normal
- **Fix**: Clean up residual SC context + check compaction filter conditions
- **Key diagnostic actions**: Distinguish base(type=1) vs cumu(type=2) → `SHOW ALTER TABLE` → be/log filter logic

### Case C2: Cumu Compaction Segfault

- **Severity**: Medium
- **Doris version**: 2.1.10
- **Symptom**: BE hits SIGSEGV core dump while running cumulative compaction
- **Root cause**: Out-of-bounds segment metadata read during a specific rowset merge scenario → null pointer
- **Fix**: Fix rowset reader boundary check (patch merged)
- **Key diagnostic actions**: `dmesg` → GDB backtrace `compaction.cpp:XXX` → extract the triggering tablet → rowset list

### Case C3: Versions Already Compacted (Compaction Race)

- **Severity**: High
- **Doris version**: 2.1+
- **Symptom**: Compaction commit fails with `[E-230]versions are already compacted, version_range=[X-Y]`
- **Root cause**: Multiple compaction tasks race on the same tablet; at commit time another task has already processed the same version range
- **Fix**: Re-check version range validity before commit
- **Key diagnostic actions**: be/log `already compacted` → `SHOW TABLET <id>` version list → check task scheduling overlap

### Case C4: High Cumu Score but Base Is Normal

- **Severity**: Medium
- **Doris version**: cloud 4.0+
- **Symptom**: Cumu score keeps rising while base score stays normal
- **Root cause**: High-frequency writes produce many cumulative points and cumu compaction throughput is insufficient
- **Fix**: Increase `max_cumulative_compaction_threads`, `compaction_task_num_per_disk`
- **Key diagnostic actions**: `be-metrics --grep compaction` → `iostat -x 1` disk IO → compare base vs cumu score

### Case C5: High Base Score but No Matching Tablet Found

- **Severity**: Medium
- **Doris version**: 3.0.10
- **Symptom**: Grafana alerts on a high base score, but `get_topn_tablets_to_compact()` shows no high-score tablet
- **Root cause**: The cloud scheduler updates the `tablet_base_max_compaction_score` metric but does not pick a tablet (slot/state/filter conditions not satisfied)
- **Key diagnostic actions**: Distinguish "score updated but not scheduled" vs "candidate exists but execution not allowed" → check slots and filter conditions

---

## Node — 7 cases

### Case N1: Auto Analyze → OOM

- **Severity**: Medium
- **Doris version**: 2.1+
- **Symptom**: BE OOM-killed after `auto_analyze` is enabled
- **Root cause**: auto_analyze full-table scans for statistics collection are not bounded by `mem_limit`
- **Fix**: Limit `auto_analyze_table_sample_percent` + mem_limit protection
- **Key diagnostic actions**: be/log MemTrackerLimiter → `SHOW ANALYZE STATUS`

### Case N2: File Cache Memory Leak

- **Severity**: High
- **Doris version**: 4.1.2
- **Symptom**: BE RSS grows continuously and is not released even without queries; file_cache usage keeps growing
- **Root cause**: file_cache LRU eviction fails under high hit rates
- **Fix**: Fix LRU eviction + set `file_cache_query_limit`
- **Key diagnostic actions**: `be-metrics --grep file_cache` → RSS vs MemTracker → `jeprof`

### Case N3: BE Keeps Coredumping

- **Severity**: Critical
- **Doris version**: 4.0.4
- **Symptom**: The same BE repeatedly core dumps and restarts
- **Root cause**: A specific query/load triggers out-of-bounds memory access or use-after-free in the segment reader
- **Key diagnostic actions**: `dmesg` / `coredumpctl` → GDB backtrace → extract query_id / load_id → replay to reproduce

### Case N4: FE BDBJE Corruption

- **Severity**: Critical
- **Doris version**: all versions
- **Symptom**: FE fails to start with `java.io.FileNotFoundException: doris-meta/bdb/0000014d.jdb`
- **Root cause**: BDBJE log file corrupted/lost (disk full or abnormal shutdown)
- **Fix**: rsync doris-meta from a healthy Follower/Observer; if the Master has no replica → use the BDBJE recovery tool
- **Key diagnostic actions**: `ls fe/doris-meta/bdb/` → `SHOW FRONTENDS` → rsync

### Case N5: Single BE Persistent Memory Leak + Abnormal CPU

- **Severity**: High
- **Doris version**: 4.1.3
- **Symptom**: A single BE's RSS grows linearly and CPU rises with it, while other BEs are normal
- **Root cause**: Suspected fragment from a specific query not released + continuous retries; the abnormal CPU is caused by memory reclamation pressure
- **Key diagnostic actions**: `jeprof` allocation hotspots → `SHOW PROC '/current_queries'` → be/log MemTracker → isolate the node for comparison

### Case N6: BE Uses 200GB Memory Right After Startup

- **Severity**: Medium
- **Doris version**: 2.1.7
- **Symptom**: Freshly started BE with no queries has RSS 200GB+
- **Root cause**: `mem_limit=80%` but `storage_page_cache_limit` etc. are not explicitly set, so a large page cache is allocated by default
- **Fix**: Explicitly set `storage_page_cache_limit` + `max_segment_cache_size`
- **Key diagnostic actions**: RSS vs mem_limit → `be-metrics --grep cache` → cache configs in be.conf

### Case N7: Memory Leak in Stress Test Scenario

- **Severity**: Medium
- **Doris version**: 4.1.7
- **Symptom**: Under YCSB high-frequency short queries, BE memory keeps rising and never falls back
- **Root cause**: Fragment contexts produced by high-frequency short queries are not reclaimed in time
- **Key diagnostic actions**: `jeprof --inuse_space` → compare before/after the stress test → fragment object counts

---

## Tablet — 3 cases

### Case T1: Abnormal Tablet Statistics

- **Severity**: Medium
- **Doris version**: 2.1+
- **Symptom**: Tablet size/row counts shown by `SHOW TABLET` / `SHOW DATA` do not match reality
- **Key diagnostic actions**: `SHOW TABLET <id>` → `ADMIN DIAGNOSE TABLET <id>` → `SHOW PROC '/statistic'`

### Case T2: S3 Hot-Cold Tiered Data Not Cleaned Up

- **Severity**: High
- **Doris version**: 2.1.7
- **Symptom**: Data cooled down to S3 is not deleted on the S3 side; storage cost keeps growing
- **Root cause**: The cooldown policy only migrates without deleting, and the expired-data cleanup task is delayed by background scheduling
- **Key diagnostic actions**: `SHOW EXPIRED POLICY` → S3 listing vs local tablets → `SHOW PROC '/trash'`

### Case T3: Write Timeout + EPOLLOUT Failure

- **Severity**: Low (but affects writes)
- **Doris version**: 3.1.3
- **Symptom**: Writes occasionally take 1 minute+; logs are full of `Fail to wait EPOLLOUT of fd=XXX: Connection timed out`
- **Root cause**: brpc socket send buffer full or the peer receives slowly → TCP send buffer congestion
- **Key diagnostic actions**: `netstat -s` retransmission stats → TCP send queue check → peer BE load

---

## Deployment — 2 cases

### Case D1: FE Fails to Start with NPE

- **Severity**: Medium
- **Doris version**: 2.1+
- **Symptom**: FE throws `NullPointerException` at startup and cannot complete bootstrap
- **Key diagnostic actions**: fe.log stacktrace → integrity of files under `fe/doris-meta/image/` → fe.conf change history

### Case D2: Newly Configured BE Fails to Start

- **Severity**: Medium
- **Doris version**: 2.1.8
- **Symptom**: A BE newly added to the cluster fails to start
- **Root cause**: Permission/path problem with `storage_root_path` in the BE config, or `priority_networks` binding failure
- **Key diagnostic actions**: be.out startup log → port conflicts via `fuser` → `priority_networks` config → directory permissions

---

## Data Lake — 5 cases

### Case DL1: Glue Catalog Pagination Loses Databases

- **Severity**: Medium
- **Doris version**: 26.0.3
- **Symptom**: `SHOW DATABASES FROM glue_catalog` returns only some of the databases
- **Root cause**: The Glue API `getAllDatabases` does not handle `NextToken` pagination correctly
- **Fix**: Fix the pagination logic
- **Key diagnostic actions**: Compare direct Glue API calls vs Doris SHOW DATABASES → fe.log `GlueCatalog`

### Case DL2: Iceberg Partitioned Table Not Recognized (Temporal Transforms)

- **Severity**: High
- **Doris version**: 26.0.3
- **Symptom**: `SHOW PARTITIONS FROM iceberg_catalog.db.tbl` returns empty
- **Root cause**: Iceberg `year/month/day` temporal partition transforms are not supported by Doris
- **Fix**: Add support for temporal partition transforms
- **Key diagnostic actions**: Iceberg `SHOW CREATE TABLE` → confirm `partitioning` → fe.log `IcebergTable`

### Case DL3: Iceberg INSERT Takes Too Long

- **Severity**: High
- **Doris version**: 2.1+
- **Symptom**: INSERT INTO iceberg_catalog.db.tbl takes far longer than expected
- **Root cause**: Multiple interactions with the catalog during the Iceberg commit phase (snapshot/commit/expireSnapshots)
- **Key diagnostic actions**: Profile the latency of each INSERT phase → Iceberg commit metrics → `iceberg_commit_batch_size`

### Case DL4: No Predicate Pushdown for JDBC External Table JOINed with Internal Table

- **Severity**: Medium
- **Doris version**: 2.1+
- **Symptom**: When a JDBC catalog external table JOINs a Doris internal table, WHERE conditions are not pushed down to the external table
- **Root cause**: The CBO does not recognize the JDBC catalog's predicate pushdown capability (`push_down_predicates` capability)
- **Fix**: Add predicate pushdown adaptation for the JDBC catalog
- **Key diagnostic actions**: EXPLAIN VERBOSE → confirm no pushdown in the scan phase → fe.log catalog capability

### Case DL5: EXPLAIN Fails After MV Base Table Schema Change

- **Severity**: Medium
- **Doris version**: 2.1+
- **Symptom**: `EXPLAIN SELECT ...` fails with "View original struct info is invalid"
- **Root cause**: Base table columns referenced by the MV definition have changed (ALTER TABLE DROP/CHANGE COLUMN), and the MV metadata is out of sync
- **Key diagnostic actions**: `SHOW CREATE MATERIALIZED VIEW` vs `SHOW CREATE TABLE` → compare column differences

---

## Resource Isolation — 5 cases

### Case R1: Spill Disk Not Taking Effect

- **Severity**: High
- **Doris version**: 4.0+
- **Symptom**: Queries still OOM after `enable_spill=true`
- **Root cause**: Spill only works for agg/join operators; the relationship between the spill trigger threshold and mem_limit is unclear
- **Key diagnostic actions**: Profile `SpillDataSize` → `be-metrics --grep spill` → confirm the triggering operator

### Case R2: MEM_LIMIT_EXCEEDED Despite Plenty of System Memory (cgroup)

- **Severity**: High
- **Doris version**: 2.1+
- **Symptom**: `mem_limit=80%` but loads fail with MEM_LIMIT_EXCEEDED while `free` shows plenty of available memory
- **Root cause**: `/proc/meminfo MemAvailable` inside a cgroup container includes reclaimable page cache, so the value is inaccurate
- **Fix**: Use cgroup `memory.limit_in_bytes - memory.usage_in_bytes` instead
- **Key diagnostic actions**: `free -h` vs cgroup memory.limit_in_bytes → be/log MemTrackerLimiter → `be-metrics --grep memory`

### Case R3: Workload Policy ConcurrentModificationException

- **Severity**: Critical
- **Doris version**: 4.1.7
- **Symptom**: Queries occasionally fail with `java.util.ConcurrentModificationException`; low probability but wide impact
- **Root cause**: The Workload Policy query routing phase concurrently modifies the policy list (iteration without locking)
- **Fix**: Use a concurrent collection or copy-on-read
- **Key diagnostic actions**: fe.log stacktrace → confirm the `WorkloadPolicyMgr` call stack → reproduce the concurrency scenario

### Case R4: Routing When a Workload Group Is Bound to Multiple Compute Groups

- **Severity**: Medium
- **Doris version**: cloud 26.0.3
- **Symptom**: When one WG is bound to multiple compute groups, query routing behavior is unclear
- **Root cause**: Under many-to-many WG–compute group bindings, the query dispatch logic is undocumented
- **Key diagnostic actions**: `SHOW WORKLOAD GROUPS` → compute group bindings → `EXPLAIN` to confirm routing

### Case R5: MV Refresh Resource Ownership Issue

- **Severity**: Medium
- **Doris version**: cloud 26.0.3
- **Symptom**: An MTMV refresh runs in one compute group but consumes the creator's workload group resource quota
- **Root cause**: The MV refresh task inherits the WG from the creator's session instead of the target compute group's default WG
- **Key diagnostic actions**: `mv_infos()` → refresh task Profile → compare WG resource usage

---

## Cloud — 5 cases

### Case CL1: Queries Still Cache Miss After Warmup

- **Severity**: Critical
- **Doris version**: 4.0.4.9
- **Symptom**: After running warmup, queries still read everything from S3; file_cache is not hit
- **Root cause**: The warmup did not cover all required segment files or delete bitmaps, or the cache TTL is too short
- **Fix**: Confirm the warmup coverage + extend the cache TTL
- **Key diagnostic actions**: `be-metrics --grep file_cache` hit ratio → compare S3 GET volume → warmup coverage

### Case CL2: BE Resources Not Released with No Queries Running

- **Severity**: High
- **Doris version**: 4.0.11
- **Symptom**: BE RSS stays at %mem_limit while `SHOW PROC '/current_queries'` is empty
- **Root cause**: Fragments of historical queries finished but their brpc channels were not released + file_cache not evicted
- **Fix**: `reset_rpc_channel` + shorten the file_cache TTL
- **Key diagnostic actions**: `SHOW PROC '/current_queries'` → `be-metrics --grep fragment` → `be-metrics --grep file_cache` → RSS vs MemTracker

### Case CL3: Query Hangs + Slow Plan Selected (Plan Race)

- **Severity**: High
- **Doris version**: cloud 26.0.4
- **Symptom**: The same query sometimes takes 200ms and sometimes hangs for minutes
- **Root cause**: CBO cost estimation under cloud mode faces unpredictable S3 IO latency + plan cache race
- **Key diagnostic actions**: Compare fast vs slow with EXPLAIN → `SET enable_plan_cache=false` → compare Profiles

### Case CL4: Meta-service Transaction Backlog

- **Severity**: High
- **Doris version**: cloud 4.1.7
- **Symptom**: Transactions pile up in meta-service, delaying FE operations
- **Root cause**: Write amplification or an elevated commit conflict rate
- **Key diagnostic actions**: Meta-service latency metrics → meta-service RPC latency in fe.log

### Case CL5: BE Abnormal Restart (No Core Dump)

- **Severity**: Medium
- **Doris version**: 4.0.4
- **Symptom**: In cloud mode the BE process exits and restarts without a core dump
- **Root cause**: Suspected brpc health check timeout triggering a watchdog kill
- **Key diagnostic actions**: be.out exit log → dmesg OOM killer → `be-metrics --grep brpc`

---

## Diagnostic Pattern Summary (Cross-Case Commonalities)

### Methodology
1. **Profile first**: In more than half of the performance cases, the first step is to look at the Profile → Plan Time vs ExecTime
2. **Distinguish base vs cumu compaction**: `type=1` = base, `type=2` = cumu → different strategies and different parameters
3. **jemalloc overhead**: RSS exceeding MemTracker by 10-20% is normal → leave headroom in mem_limit
4. **Catalog scan range latency**: For S3/HDFS/Glue/Iceberg, slowness is usually not in IO but in RPC/metadata/partition enumeration
5. **brpc problems are not necessarily network problems**: E11/EAGAIN usually means thread pool/concurrency issues, not network connectivity
6. **Stop the bleeding before root-causing**: `reset_rpc_channel`, kill query, reduce concurrency parameters → preserve on-site evidence (pstack/jstack/heap dump) → then analyze

### High-Frequency Root Cause Categories

| Category | Related Cases | Share |
|------|----------|------|
| RPC/concurrency/thread pool | I4, Q3, CL2 | ~20% |
| Memory leak/overflow | N1, N2, N5, N7, R1, R2 | ~25% |
| Compaction scheduling/race | C1, C3, C4, C5 | ~15% |
| Catalog/metadata interaction | Q1, DL1, DL2, DL3 | ~15% |
| Misconfiguration/version compatibility | Q2, D2, N6 | ~10% |
| Code bugs (null pointer/concurrency) | R3, C2, I5 | ~15% |

---

## How to Use

Reference cases from this index in the doris-debug skill's case files:

```markdown
## Related cases
- [Q3] Exchange brpc E11 fanout — exchange RPC hits EAGAIN during peak hours; reduce parallel_exchange_instance_num
- [I4] Import RPC timed out — heavy work pool saturated; tablet_writer_open times out
```

When troubleshooting, search this index first for cases with similar symptoms to avoid re-investigating known issues.
