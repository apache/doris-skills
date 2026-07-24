---
type: reference
category: import
keywords: [tablet writer, RPC timeout, heavy work pool, brpc_heavy, import stuck]
---

# Case-002: 导入 RPC Timed Out — BE Heavy Work Pool 打满

## Environment

- Doris version: 4.0.9 (cloud)
- Architecture: storage-compute separation

## Symptom

导入偶发失败，日志显示：
```
VNodeChannel[...] node=172.31.36.239:8061 open failed ...
RPC call is timed out ... Reached timeout=60000ms
```
随后 coordinator cancel 整条 load。后续日志：
```
failed to prepare rowset: txn is not in 1 state, txn_status=4
```
重试后成功，说明是瞬时拥塞而非数据问题。

## Key evidence

```
2026-07-08 00:58:33.541  开始: query_id=8456cc28099544e9, query type: LOAD
2026-07-08 00:58:33.551  open tablets channel: tablets num=29, senders=74
2026-07-08 00:59:57.677  open failed: RPC call is timed out (60s)
                        → cancel other node channels
2026-07-08 01:00:57.649  txn_status=4 (load channel 已被 cancel)
```

同一窗口（00:47~01:53）内 `Reached timeout=60000ms @172.31.36.239:8061` 成簇出现，不是孤立超时。

日志中未出现 `fail to offer request to the work pool`（queue offer 失败签名）。

## Investigation

### Step 1: 代码路径确认

```
VNodeChannel::_open_internal
  → PBackendService_Stub::tablet_writer_open(timeout=60s)
  → PInternalService::tablet_writer_open
  → _heavy_work_pool.try_offer(LoadChannelMgr::open)
  → LoadChannel::open
  → TabletsChannel::open / _open_all_writers
```

`tablet_writer_open` 在 BE 侧进入 `brpc_heavy` work pool 后执行 load channel/open writer。超时=60s 由 `tablet_writer_open_rpc_timeout_sec` 控制。

### Step 2: 区分 offer 失败 vs 执行阻塞

| 日志签名 | 含义 |
|---------|------|
| `fail to offer request to the work pool` | heavy pool 队列满，请求被拒绝 |
| `RPC call is timed out`（无 offer 失败日志） | 请求进入 heavy pool 后执行过慢或排队超时 |

当前是后者：请求进入了 heavy pool 但执行超时。

### Step 3: 历史比对

历史有同一模式：目标 BE `brpc_heavy_work_pool_threads=256` 在高并发导入时全部 active thread 被 long-running open/write 占满，后续请求排队等待 → 超时。

临时缓解方式：`brpc_heavy_work_pool_threads 256→384`，但没闭环到具体卡点（故障时未保留 pstack）。

## Root Cause

目标 BE 的 `brpc_heavy` work pool 在导入高并发时被 `tablet_writer_open` / `_open_all_writers` 占满，active heavy 线程长期被占导致后续请求排队超时。

## Fix

- **短期**: 降低/错峰同一 compute group 上的大 insert/load 并发；重试即可恢复
- **中期**: 调大 `brpc_heavy_work_pool_threads`（256→384），但注意这只是增加排队容量，不是根治
- **故障时务必保留现场**: 在重启 BE 之前先 `pstack` 卡住的进程，才能定位具体卡点（writer/open、IO、cgroup stall 等）
- **长期**: 分析 heavy pool 中 long-running 操作的耗时分布，考虑拆分或限流

## Key diagnostic actions

1. be/log 搜索 `RPC call is timed out` → 确认目标 BE 和时间窗口
2. 确认同一窗口是否成簇出现（单点瞬时拥塞 vs 持续问题）
3. 检查 `fail to offer request to the work pool` 签名（区分 offer 失败 vs 执行阻塞）
4. 故障窗口保留 pstack 再重启 BE
5. 检查 `tablet_writer_open_rpc_timeout_sec` 配置
