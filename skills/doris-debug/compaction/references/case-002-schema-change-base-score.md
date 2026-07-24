---
type: reference
category: compaction
keywords: [base compaction, schema change, SC residue, tablet state, compaction score ghost]
---

# Case-002: Schema Change 残留导致 Base Compaction Score 虚高

## Environment

- Doris version: cloud 4.0+
- Architecture: storage-compute separation

## Symptom

Grafana 监控显示某 BE 的 base compaction score 持续偏高：
- base score: max 1490, avg 1370
- cumu score: max 79, avg 32.5（正常）

告警触发但集群无查询异常。用户怀疑 compaction 资源不足。

## Key evidence

```
be/log:
get_topn_compaction_score ... type=1  → score 高（base）
get_topn_compaction_score ... type=2  → score 正常（cumu）
```

但 `get_topn_tablets_to_compact()` 实际提交的 compaction 任务数与 score 不成比例。

Grafana 截图时间范围 2026-07-01~07-07，base score 缓慢上升而非突发。

历史检查：同一集群有 Schema Change 操作记录。

## Investigation

### Step 1: 区分 Base vs Cumulative

Doris compaction 枚举：
```
BASE_COMPACTION = 1       → base score
CUMULATIVE_COMPACTION = 2 → cumu score
```

`get_topn_compaction_score ... type=1` 才是 base 分数，`type=2` 是 cumu。不能混着看。

当前 base high / cumu normal → 是 base compaction 被阻塞，不是全局 compaction 资源不足。

### Step 2: 代码核对

cloud 调度调用 `get_topn_tablets_to_compact()` 计算最高分 tablet 并把值写入：
```
tablet_base_max_compaction_score    → Grafana 取值源
tablet_cumulative_max_compaction_score
```

但 score 更新 ≠ 实际 pick tablet 执行。调度器在 pick 前会检查：
- tablet_state 是否允许 compaction
- 是否有 slot 可用
- SC（Schema Change）上下文是否允许
- 其他过滤条件

### Step 3: 过滤条件排查

SC 操作在 tablet 上创建了 base compaction 候选（因为 SC 会生成新的 rowset 需要合并），但 SC 上下文未清理时，`tablet_state` 或 SC 状态会阻止 compaction 执行。

结果：base score 持续计算并写入 metric → Grafana 告警，但实际 compaction 不执行 → score 得不到缓解。

## Root Cause

Schema Change 操作产生的残留 SC 上下文导致 base compaction 候选 tablet 无法被 compaction 调度器执行。

这不是 "缺少 compaction 资源" 或 "cumu point 太多"，而是 "有候选但不允许执行"。

## Fix

1. 清理残留 SC 上下文（`SHOW ALTER TABLE` 确认 SC 状态 → `CANCEL ALTER` 清理）
2. 检查 compaction 调度过滤逻辑中 SC 相关的条件判断
3. 不要盲目增加 compaction 线程或磁盘并发——当前不是线程/IO 不足，是候选被过滤

## Key diagnostic actions

1. 区分 base(type=1) vs cumu(type=2) score（不同问题方向）
2. `SHOW ALTER TABLE` 检查是否有 pending/failed SC 操作
3. be/log 搜索 `get_topn_tablets_to_compact` → 确认过滤逻辑
4. 如果 base score 高但找不到高分 tablet（C5 场景），检查 cloud 调度 slot/状态/过滤条件
5. `SHOW PROC '/cluster_health/tablet_health'` 确认是否有 tablet 版本异常
