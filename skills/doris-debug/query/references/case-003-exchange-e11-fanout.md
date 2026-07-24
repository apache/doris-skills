---
type: reference
category: query
keywords: [E11, exchange, brpc, fanout, Resource temporarily unavailable, parallel_exchange_instance_num]
---

# Case-003: Exchange brpc E11 During Peak Hours — Excessive Concurrent Fragments Saturate the RPC Send Side

## Environment

- Doris version: 4.0.7 (cloud)
- Architecture: storage-compute separation, 3 BE in compute group

## Symptom

During the 10:00~10:30 peak window, a large number of queries and loads failed with:
```
failed to send brpc when exchange, error=Resource temporarily unavailable,
error_text=[E11]Resource temporarily unavailable @10.244.0.29:8060
```
Accompanied by `RPC meet failed: [E11]`, `pipeline_fragment_context.cpp:171] cancel`, and load-side `cancel node channel`.

## Key evidence

### Time distribution (E11 hit statistics)

| Time | E11 log lines | Distinct query_id |
|------|---------------|-------------------|
| 10:00 | 7,282 | 46 |
| 10:03 | 35,639 | 58 |
| 10:10 | 248 | 2 |
| 10:25 | 79,391 | 107 |
| 10:26 | 47,766 | 125 |
| 10:27 | 29,522 | 68 |

The peak is concentrated in 10:25~10:27; there are 406 distinct query_ids across the whole window.

### Target-side distribution

```
10.244.0.29:8060  → 144,181 lines
10.244.0.20:8060  →  55,419 lines
10.244.0.10:8060  →     248 lines
```

E11 is concentrated on two BEs, not evenly distributed across the cluster. Sender-side samples:
```
10.244.0.10 → 10.244.0.29/20
10.244.0.20 → 10.244.0.29
```

### Fragment concurrency

```
10:25:01  fragment_num: 1575 / 1556 / 1326  (three BEs)
10:25:21  fragment_num: 2056  (10.244.0.10)
10:26:42  fragment_num: 2108
10:27:12  fragment_num: 2444
```

Per-minute fragment start lines from BE `fragment_mgr.cpp`:
```
10:17: 15,296
10:20:  9,020
10:25:  7,994
10:26:  6,902
10:27:  8,046
```

### Parallelism configuration

```sql
parallel_exchange_instance_num         = 100    ← key
parallel_fragment_exec_instance_num    = 8
parallel_pipeline_task_num             = 0
```

### Ruled out

The following signals were NOT found in the logs:
- `pthread_create failed` / `failed to create thread` → not thread pool exhaustion
- `queue is full` / `EOVERCROWDED` → not queue overflow
- `too many open files` → not FD exhaustion
- `MEM_LIMIT_EXCEEDED` → not a memory limit

## Investigation

### Step 1: Confirm the error source

Code path (4.0.7):
```
be/src/pipeline/exec/exchange_sink_buffer.h
  ExchangeSendCallback::call()
    → brpc::Controller::Failed()
    → "failed to send brpc when exchange, error={}, error_text={}"
```

This is a failure on the BE-to-BE exchange RPC send path — not a SQL semantic error, and not an FE thrift/mysql thread pool rejection.

### Step 2: Distinguish E11 brpc from pthread_create EAGAIN

Both show "Resource temporarily unavailable", but they mean completely different things:

| Signal | Meaning |
|--------|---------|
| `[E11]` + `failed to send brpc when exchange` | brpc socket send-side EAGAIN: socket send buffer full or peer receiving slowly |
| `pthread_create failed (EAGAIN)` + `cgroup: fork rejected by pids controller` | thread/pids limit reached |

The current logs are the former; do not treat this by expanding thread pools.

### Step 3: Determine the failure scope

E11 is concentrated on two BEs (29 and 20); BE 10 is barely affected. In the same window, FE load job dispatch ran 398~1360 times per minute — loads and queries were highly concurrent at the same time.

## Root Cause

High-concurrency LOAD + SELECT overlapping, with `parallel_exchange_instance_num=100` plus the default pipeline parallelism, causes the number of actually concurrent fragment/exchange RPCs to far exceed what the brpc sockets can handle. The send-side socket send buffer fills up → the brpc controller returns E11 → query/load cancel.

This is a known problem family; historical cases of the same type were all mitigated by lowering exchange/pipeline parallelism.

## Fix

- **Short term**: Lower `parallel_exchange_instance_num` (100 → 50 or 32) to control exchange fanout
- **Mid term**: Add Workload Group concurrency/queueing limits for the peak-hour workload
- **Long term**: Backport apache/doris PR #50113 (one rpc send multi blocks, reducing the number of RPCs)

Tuning order:
1. First adjust only `parallel_exchange_instance_num`: 100 → 50 and observe
2. If it still reproduces → lower further to 32, or combine with lowering `parallel_pipeline_task_num` to 1
3. Do not blindly increase thread pool parameters (there is no evidence of thread pool rejection; adding threads only amplifies E11)

## Key diagnostic actions

1. Confirm the error prefix is `failed to send brpc when exchange` (confirms the exchange brpc path)
2. Tally the E11 target BE distribution: single node vs whole cluster (different remediation directions)
3. Extract fragment_num / fragment start counts within the window (confirm the fanout scale)
4. Search to rule out pthread_create / pids / FD exhaustion signals
5. Confirm the current values of `parallel_exchange_instance_num` / `parallel_pipeline_task_num`
6. Search historical similar cases: the `failed to send brpc when exchange, [E11]` problem family
