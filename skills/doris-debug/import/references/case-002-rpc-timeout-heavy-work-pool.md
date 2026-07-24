---
type: reference
category: import
keywords: [tablet writer, RPC timeout, heavy work pool, brpc_heavy, import stuck]
---

# Case-002: Import RPC Timed Out — BE Heavy Work Pool Saturated

## Environment

- Doris version: 4.0.9 (cloud)
- Architecture: storage-compute separation

## Symptom

Imports fail intermittently; logs show:
```
VNodeChannel[...] node=172.31.36.239:8061 open failed ...
RPC call is timed out ... Reached timeout=60000ms
```
The coordinator then cancels the entire load. Subsequent logs:
```
failed to prepare rowset: txn is not in 1 state, txn_status=4
```
Retrying succeeds, indicating transient congestion rather than a data problem.

## Key evidence

```
2026-07-08 00:58:33.541  start: query_id=8456cc28099544e9, query type: LOAD
2026-07-08 00:58:33.551  open tablets channel: tablets num=29, senders=74
2026-07-08 00:59:57.677  open failed: RPC call is timed out (60s)
                        → cancel other node channels
2026-07-08 01:00:57.649  txn_status=4 (load channel already cancelled)
```

Within the same window (00:47~01:53), `Reached timeout=60000ms @172.31.36.239:8061` appears in clusters — not isolated timeouts.

The logs do not contain `fail to offer request to the work pool` (the queue offer failure signature).

## Investigation

### Step 1: Confirm the Code Path

```
VNodeChannel::_open_internal
  → PBackendService_Stub::tablet_writer_open(timeout=60s)
  → PInternalService::tablet_writer_open
  → _heavy_work_pool.try_offer(LoadChannelMgr::open)
  → LoadChannel::open
  → TabletsChannel::open / _open_all_writers
```

On the BE side, `tablet_writer_open` enters the `brpc_heavy` work pool and then executes load channel/open writer. The 60s timeout is controlled by `tablet_writer_open_rpc_timeout_sec`.

### Step 2: Distinguish Offer Failure vs Execution Blocking

| Log signature | Meaning |
|---------|------|
| `fail to offer request to the work pool` | heavy pool queue is full; the request is rejected |
| `RPC call is timed out` (no offer failure log) | the request entered the heavy pool but executed too slowly or timed out while queued |

The current case is the latter: requests entered the heavy pool but timed out during execution.

### Step 3: Historical Comparison

History shows the same pattern: on the target BE with `brpc_heavy_work_pool_threads=256`, all active threads are occupied by long-running open/write operations under high-concurrency imports, so subsequent requests queue up and time out.

Temporary mitigation: `brpc_heavy_work_pool_threads 256→384`, but the specific blocking point was never pinned down (no pstack was captured during the incident).

## Root Cause

Under high-concurrency imports, the target BE's `brpc_heavy` work pool is saturated by `tablet_writer_open` / `_open_all_writers`. Active heavy threads remain occupied for a long time, causing subsequent requests to queue and time out.

## Fix

- **Short term**: Reduce or stagger the concurrency of large insert/load jobs on the same compute group; retrying recovers
- **Medium term**: Increase `brpc_heavy_work_pool_threads` (256→384), but note this only adds queuing capacity — it is not a cure
- **Always preserve the scene during an incident**: `pstack` the stuck process before restarting the BE, so the specific blocking point can be located (writer/open, IO, cgroup stall, etc.)
- **Long term**: Analyze the latency distribution of long-running operations in the heavy pool; consider splitting them up or applying rate limiting

## Key diagnostic actions

1. Search be/log for `RPC call is timed out` → confirm the target BE and time window
2. Confirm whether timeouts appear in clusters within the same window (transient congestion at a single point vs a persistent problem)
3. Check for the `fail to offer request to the work pool` signature (distinguishes offer failure from execution blocking)
4. Capture pstack during the incident window before restarting the BE
5. Check the `tablet_writer_open_rpc_timeout_sec` configuration
