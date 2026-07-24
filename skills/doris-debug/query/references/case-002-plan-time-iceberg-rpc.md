---
type: reference
category: query
keywords: [plan time, nereids, iceberg, create scan range, catalog rpc, slow query]
---

# Case-002: FE Plan Time 10 分钟（Iceberg 外表 Create Scan Range RPC 爆炸）

## Environment

- Doris version: 4.1.3 (Nereids optimizer)
- Architecture: shared-nothing
- Catalog type: Iceberg external catalog

## Symptom

SQL `SELECT * FROM iceberg.db.table WHERE lower(name) NOT LIKE '%xxx%'` 耗时 10 分 8 秒。
同一查询多次执行，每次都是 ~10 分钟。用户怀疑 BE 执行慢或 S3 读慢。

## Key evidence (Profile)

```
Profile ID: a6e9d417718d4cf6-88857f81140da87f

Total:                         10min8sec
  Plan Time:                   10min8sec    ← 占 100%
    Nereids Translate Time:    10min8sec
    Finalize Scan Node Time:   10min8sec
    Create Scan Range Time:    10min1sec    ← 核心耗时
    Get Splits Time:           6sec323ms

  Schedule Time:               4ms
  Wait and Fetch Result Time:  214ms
  Fetch Result Time:           213ms

FILE_SCAN_OPERATOR:
  ExecTime:                    211.882ms    ← BE 执行只有 200ms
  RowsProduced:                540
  ScanRows:                    593
  ScanBytes:                   1021.08 KB
  FileNumber:                  64
  partitions:                  63

Is Nereads:                    Yes
Is Cached:                     No
```

**结论：BE 执行只有 214ms/1MB，问题完全在 FE planning 阶段。**

## Investigation

### Step 1: 确认 Plan Time 占比

`Plan Time=10min8sec` 等于 Total，BE `ExecTime=211ms`，排除 BE compute / IO 瓶颈。

### Step 2: 拆解 Nereids planning 阶段

`Nereids Translate Time` = 10min8sec → 不是 FE lock / GC（`Garbage Collect During Plan Time=52sec` 只占一小部分）。

`Finalize Scan Node Time` = 10min8sec → 问题在最终化 scan node 阶段。

`Create Scan Range Time` = 10min1sec → 创建 scan range 是核心耗时。

`Get Splits Time` = 6sec → 获取文件分片只花了 6 秒。

### Step 3: 代码核对

4.1.3 代码中 Iceberg catalog 在 Create Scan Range 阶段会：

1. 遍历每个 partition（64 个文件 / 63 个分区）
2. 每次 `getManifestFiles()` → 调用 `UpdateRunningStatus()` → 触发 `msClient.updateInstance()` RPC 到 meta-service
3. 每次 RPC 约 200ms
4. 反复调用累积 → 10min+

```
CreateScanRange
  → for each partition:
      → getManifestFiles()
        → UpdateRunningStatus()
          → msClient.updateInstance()   ← 每次 ~200ms RPC
```

这与 BE S3 list 或 scan 无关，纯粹是 FE-meta-service 之间的 RPC 次数过多。

## Root Cause

Nereids 在 Create Scan Range 阶段对 Iceberg 外表的处理中，每次获取 manifest 文件时调用了不必要的 meta-service RPC（`updateInstance`），且这个 RPC 对每个 partition 都执行一次。64 个文件 × 每次 ~200ms → 10 分钟。

## Fix

- **短期**: 调大 `iceberg_manifest_cache_refresh_interval_s`，减少 manifest 重新获取频率
- **长期**: 改进 Create Scan Range 阶段，减少对 meta-service 的重复 RPC 调用（合并批量获取，或移除不必要的 `updateInstance`）

## Key diagnostic actions

1. Profile → 确认 `Plan Time` 占比（而不是 BE ExecTime）
2. 确认 `Is Nereids=Yes`
3. 拆解 Plan Time 子阶段：`Nereids Translate Time` → `Finalize Scan Node Time` → `Create Scan Range Time`
4. 对比 `Get Splits Time`（正常）和 `Create Scan Range Time`（异常），确认问题在创建 scan range 而非获取文件列表
5. 如果是 Iceberg/Hive 外表 → 检查 manifest/catalog RPC 耗时
