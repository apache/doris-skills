---
type: reference
category: node
keywords: [memory leak, scanner pileup, pipeline fragment, RSS growth, jeprof, QueryCache, OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY]
---

# Case-003: Continuous BE Memory Growth + Scanner Pileup (Pipeline Fragments Not Released)

## Environment

- Doris version: 4.1.3 (cloud)
- Architecture: storage-compute separation, multiple BEs

## Symptom

A single BE's RSS grows linearly up to 228GB (limit 226GB), CPU rises as well, while other BEs are normal.

`/profile` shows:
```
VmRSS: 228.56 GB
Pipeline fragment contexts still running: 3,641
_num_running_scanners: 1  → appears 4,686 times (a healthy BE has only 1)
QueryCache@cache Current: 45.56 GB
DataPageCache Current: 410.65 MB  ← normal
SegmentCache Current: 0            ← normal
```

`MemoryGC` scans find 1000+ running query/load entries but no large task to cancel.

## Key evidence

### Pipeline dump analysis

The abnormal BE has 3,641 pipeline fragment contexts still running (healthy BEs are far below this).

Top 10 stuck query_ids (sorted by elapsed):

| Rank | Query ID | Max Elapsed | Stuck point |
|------|----------|-------------|------|
| 1 | 1de87894... | 19.34min | OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY |
| 2 | 9dac5480... | 19.04min | OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY |
| 3-10 | ... | 15~19min | same as above |

Common traits of all stuck queries:
- `_num_running_scanners=0` (scanners have stopped)
- `query_timeout_second=1200`, `is_timeout=false`
- Query tracker `Current=64B, Peak=13.60MB` (per-query memory footprint is small)
- Common stuck point: `OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY` / runtime filter NOT_READY

### FE logs (same time window)

```
StmtExecutor.execute begin to execute query: ~183,002 entries
LoadAction.streamLoad: ~215,684 entries
Use query cache: ~8,988 entries
```

Extremely high concurrent queries and Stream Loads during the same window.

The abnormal BE `10.20.80.195` received the most Stream Load redirects (27,152 times).

### Memory allocation hotspots

QueryCache accounts for 45.56GB (the largest single category), but DataPageCache/SegmentCache are very low.

## Investigation

### Step 1: Rule out DataPageCache/SegmentCache

Metrics show both are far below other BEs (DataPageCache 410MB vs several GB on healthy BEs) — ruled out.

### Step 2: Focus on Scanner/Pipeline pileup

3,641 pipeline fragment contexts are still running; `_num_running_scanners` appears 4,686 times (vs only 1 on a healthy BE). This means many fragments have stopped their scanners but have not exited.

### Step 3: Stuck point analysis

All stuck queries are blocked on `OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY` (runtime filter NOT_READY), not on an active scanner. These fragments are waiting for other nodes to broadcast runtime filters, but for some reason the filters never arrive → fragments never exit → contexts pile up.

### Step 4: QueryCache investigation

QueryCache at 45.56GB is a significant consumer. High-frequency queries hit the cache (8,988 `Use query cache` entries in the FE log), but QueryCache memory is not precisely tracked by MemTracker and may leave native memory fragmentation after pruning.

### Step 5: Uneven Stream Load routing

The abnormal BE received the most Stream Loads (27,152 times), about 17% more than other BEs. Not an order-of-magnitude difference, but combined with scanner pileup it may amplify memory pressure.

## Root Cause (multi-factor)

1. **Pipeline fragment retention**: Large numbers of fragments are stuck on `OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY` (runtime filter wait timeout or never satisfied); fragment contexts are not released
2. **QueryCache memory usage**: 45GB+ QueryCache is not sufficiently pruned under scan pressure
3. **Skewed Stream Load routing**: The abnormal BE carries more ingestion traffic

Factor 1 dominates: scanners have stopped, but fragments wait for runtime filters → contexts pile up → memory and CPU (memory GC pressure) keep growing.

## Fix

- **Short-term mitigation**: Restart the abnormal BE to clear piled-up fragments (capture pstack + heap dump before restarting for later analysis)
- **Mid-term**:
  - Review runtime filter timeout configuration (`runtime_filter_wait_time_ms`) to prevent fragments from waiting indefinitely
  - Evaluate temporarily lowering/disabling QueryCache to verify whether RSS drops
  - Balance Stream Load routing
- **Long-term**: Fix the fragment context cleanup mechanism after runtime filter wait timeout

## Key diagnostic actions

1. `/profile` or pipeline dump → number of pipeline fragment contexts still running
2. Sort by elapsed to find top query_ids → confirm the common stuck point
3. be/log `MemoryGC` scan results (check whether there is a cancellable large task)
4. `jeprof --inuse_space` to confirm allocation hotspots
5. `be-metrics --grep cache` to break down per-cache usage
6. FE log statistics for query/ingestion volume in the same window
7. Capture `top -H` / `pstack` on the abnormal BE to preserve the scene
