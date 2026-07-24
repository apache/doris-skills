---
type: reference
category: cloud
keywords: [warmup, file_cache, cache miss, route snapshot, tablet mapping, empty batch]
---

# Case-001: Warmup 后查询仍全量读 S3 — FE 下发空 Batch

## Environment

- Doris version: 4.0.4.9 (cloud)
- Architecture: storage-compute separation, 3 BE in compute group `batch_data`

## Symptom

执行 `WARM UP TABLE ods.ods_event_ri` 后，`SHOW WARM UP JOB` 显示所有 91 个 job 都是 `FINISHED`、`AllBatch=0`，耗时仅秒级。但后续查询仍从 S3 全量读取，本地 file_cache 命中率为 0。

用户反复执行 warmup 和 `force` warmup，结果相同。

## Key evidence

### FE 日志

```
send warm up request. job_id=..., batch_id=0, job_sizes=0, request_type=SET_JOB
```
共 273 次（91 个 job × 3 台 BE），全部 `job_sizes=0`。

FE 计算了非零 warm-up size（每个 job 约 0.2~0.5GB），但下发给 BE 时 batch 为空。

### BE 日志

```
SET_BATCH ... jobs size=0
pending_job_size=0|finish_job_size=0
CLEAR_JOB
```

每次都是 `jobs size=0` → 状态查询 pending=0 → 立即 `CLEAR_JOB`。

BE 日志中没有出现 `download_segment_file`、`warm_up_cache_async`、`FileCacheBlockDownloader` 等实际下载/预热关键词。

## Investigation

### Step 1: 确认 warmup job 状态

`SHOW WARM UP JOB` 显示 `FINISHED` + `AllBatch=0`。排除下载失败——根本没有触发下载。

### Step 2: 代码路径核对（4.0.4.9）

```
CacheHotspotManager.warmUpNewClusterByTable()
  1. 按分区累加 partition.getDataSize(true)
     → 打印非零 warm up size
  2. 将分区 tablet 与 CloudTabletRebalancer.getSnapshotTabletsInPrimaryByBeId()
     做交集
     → 只有落在该 BE primary snapshot 里的 tablet 才加入 beToWarmUpTablets
  3. splitBatch() 对空 tablet 列表 → 空 batch
  4. CloudWarmUpJob.buildJobMetas() batch 为空 → 空 job_metas
  5. BE CloudBackendService::warm_up_tablets() 收到空 job_metas → 无 pending 任务
  6. FE 看到 pending=0 → 标为 FINISHED 并清理
```

### Step 3: 根因确认

FE route/rebalancer snapshot 中没有目标分区的 tablet 映射到这 3 台 BE。
可能原因：route snapshot 刚初始化、BE 替换/扩缩容后未稳定、或 snapshot 与当前实际查询路由不一致。

## Root Cause

不是 BE 下载失败，而是 FE 生成的 per-BE warm-up tablet batch 为空。原因是 cloud tablet rebalancer snapshot 中没有目标表分区 tablet 到目标 BE 的映射。

`force` 参数无法解决此问题（4.0.4.9 代码中 `force` 只绕过 cache capacity 检查，不修复空 tablet 映射）。

## Fix

- **验证 route snapshot**: 在重跑 warmup 前确认 `CloudTabletRebalancer.getSnapshotTabletsInPrimaryByBeId` 对目标 BE 返回非空且包含目标表格分区 tablet
- **等待 route 稳定**: 如果是刚扩缩容，等 cloud tablet rebalancer 完成一轮稳定 route 后再跑 warmup
- **用 FE/BE 日志验证**: 重跑时确认 `job_sizes > 0`，BE 日志 `jobs size > 0`、`pending_job_size` 曾经非 0
- **代码改进**: 当 `warm up size > 0` 但所有 BE batch 为空时，不应返回 `FINISHED`，应报错/取消并提示 route snapshot 无目标 tablet

## Key diagnostic actions

1. `SHOW WARM UP JOB` 检查 `AllBatch` — 如果为 0，问题不在下载
2. FE 日志搜索 `send warm up request` → 确认 `job_sizes` 是否为 0
3. BE 日志搜索 `SET_BATCH` → 确认 `jobs size` 是否为 0
4. BE 日志搜索 `download_segment_file` → 如果完全不存在，确认下载从未触发
5. 检查 `CloudTabletRebalancer` snapshot 状态
