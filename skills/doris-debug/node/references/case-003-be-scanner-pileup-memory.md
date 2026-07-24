---
type: reference
category: node
keywords: [memory leak, scanner pileup, pipeline fragment, RSS growth, jeprof, QueryCache, OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY]
---

# Case-003: BE 内存持续增长 + Scanner 堆积（Pipeline Fragment 未释放）

## Environment

- Doris version: 4.1.3 (cloud)
- Architecture: storage-compute separation, multiple BE

## Symptom

单台 BE RSS 持续线性增长至 228GB（limit 226GB），CPU 也随之升高，其他 BE 正常。

`/profile` 显示：
```
VmRSS: 228.56 GB
Pipeline fragment contexts still running: 3,641
_num_running_scanners: 1  → 出现 4,686 次（另一台正常 BE 只有 1 次）
QueryCache@cache Current: 45.56 GB
DataPageCache Current: 410.65 MB  ← 正常
SegmentCache Current: 0            ← 正常
```

`MemoryGC` 扫描到 1000+ running query/load 但无大任务可取消。

## Key evidence

### Pipeline dump 分析

异常 BE 上有 3,641 个 pipeline fragment context 仍在运行（正常 BE 远低于此）。

Top 10 滞留 query_id（按 elapsed 排序）：

| Rank | Query ID | Max Elapsed | 卡点 |
|------|----------|-------------|------|
| 1 | 1de87894... | 19.34min | OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY |
| 2 | 9dac5480... | 19.04min | OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY |
| 3-10 | ... | 15~19min | 同上 |

所有滞留 query 的共同特征：
- `_num_running_scanners=0`（scanner 已停止）
- `query_timeout_second=1200`, `is_timeout=false`
- Query tracker `Current=64B, Peak=13.60MB`（单 query 内存占用很小）
- 共同卡点：`OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY` / runtime filter NOT_READY

### FE 日志（同时段）

```
StmtExecutor.execute begin to execute query: ~183,002 条
LoadAction.streamLoad: ~215,684 条
Use query cache: ~8,988 条
```

同时段有极高并发的查询和 Stream Load。

异常 BE `10.20.80.195` 接收到的 Stream Load 重定向次数最高（27,152 次）。

### 内存分配热点

QueryCache 占 45.56GB（最大单类占用），但 DataPageCache/SegmentCache 很低。

## Investigation

### Step 1: 排除 DataPageCache/SegmentCache

监控显示两者远低于其他 BE（DataPageCache 410MB vs 正常 BE 数 GB），排除。

### Step 2: 聚焦 Scanner/Pipeline 堆积

3,641 个 pipeline fragment contexts 仍在运行，_num_running_scanners 出现 4,686 次（对比正常 BE 仅 1 次）。说明大量 fragment 已经停止 scanner 但未退出。

### Step 3: 卡点分析

所有滞留 query 卡在 `OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY`（runtime filter NOT_READY），不是 active scanner。说明这些 fragment 在等待其他节点广播 runtime filter，但由于某种原因 filter 永远不会到达 → fragment 永远不退出 → context 堆积。

### Step 4: QueryCache 调查

QueryCache 45.56GB 是显著占用。高频查询命中 cache（FE 日志 8,988 次 `Use query cache`），但 QueryCache 的内存占用不会被 MemTracker 精确追踪，可能在被 prune 后留下 native 内存碎片。

### Step 5: Stream Load 路由不均

异常 BE 接收了最多 Stream Load（27,152 次），比其他 BE 高约 17%。虽不是数量级差异，但叠加 scanner pileup 可能加剧内存压力。

## Root Cause（多因素）

1. **Pipeline fragment 滞留**: 大量 fragment 卡在 `OLAP_SCAN_OPERATOR_FILTER_DEPENDENCY`（runtime filter 等待超时或永不满足），fragment context 不释放
2. **QueryCache 内存占用**: 45GB+ QueryCache 在扫描压力下未被充分 prune
3. **Stream Load 路由偏斜**: 异常 BE 承担更多导入流量

主要是因素 1：Scanner 虽已停止，但 fragment 等待 runtime filter → context 堆积 → 内存和 CPU（memory GC 压力）持续增长。

## Fix

- **短期止血**: 重启异常 BE 清除堆积 fragment（重启前保留 pstack + heap dump 用于后续分析）
- **中期**: 
  - 排查 runtime filter 超时配置（`runtime_filter_wait_time_ms`），避免 fragment 无限等待
  - 评估临时降低/关闭 QueryCache 验证 RSS 是否下降
  - 均衡 Stream Load 路由
- **长期**: 修复 runtime filter 等待超时后 fragment context 的清理机制

## Key diagnostic actions

1. `/profile` 或 pipeline dump → pipeline fragment contexts still running 数量
2. 按 elapsed 排序找 Top query_id → 确认共同卡点
3. be/log `MemoryGC` 扫描结果（确认是否有可取消的大任务）
4. `jeprof --inuse_space` 确认分配热点
5. `be-metrics --grep cache` 分解各类 cache 占用
6. FE 日志统计同时段查询/导入量
7. 异常 BE 上 `top -H` / `pstack` 保留现场
