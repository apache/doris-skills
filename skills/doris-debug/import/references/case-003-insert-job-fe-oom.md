---
type: reference
category: import
keywords: [INSERT INTO, OOM, JobManager, job leak, FE memory, jmap, mem_leak]
---

# Case-003: INSERT INTO Job 不清理导致 FE 内存打爆反复 OOM

## Environment

- Doris version: 26.0.3 (cloud)
- Architecture: storage-compute separation

## Symptom

FE 内存持续增长直至 OOM，重启后恢复但数小时/数天后再次 OOM。

`jmap -histo` 显示大量 `InsertJob` 对象存活。

`SHOW LOAD` / `SHOW INSERT` 显示数千个历史 job（状态均为 FINISHED 或 CANCELLED），远超正常范围。

## Investigation

### Step 1: 确认 OOM 类型

```bash
jmap -heap <fe_pid> | head -20
# Old Gen 使用率接近 100%，频繁 Full GC

jmap -histo <fe_pid> | head -30
# InsertJob / AbstractJob 对象数量异常高
```

### Step 2: 确认 job 数量

```sql
SHOW LOAD ORDER BY CreateTime DESC LIMIT 100;
-- 大量 FINISHED/CANCELLED 状态的 INSERT INTO job

SELECT COUNT(*) FROM information_schema.loads WHERE Type='INSERT';
-- 返回数字异常大（数千甚至上万）
```

### Step 3: 代码核对

INSERT INTO job 流程：
1. INSERT INTO 语句被注册为 job（包含 `InsertJob` 对象）
2. Job 执行完成后状态变为 FINISHED
3. `JobManager` 应将 FINISHED job 从内存中移除
4. Bug: `JobManager` 未清理 FINISHED job
5. FE restart 时 `JobManager.reload()` 从元数据加载所有历史 job → 反复 OOM

```
FE start
  → JobManager.reload()
    → 从 doris-meta 加载所有历史 INSERT job
      → InsertJob 对象全部进入 heap
        → 累积数千个 → Old Gen 满 → Full GC → OOM
```

## Root Cause

INSERT INTO job 完成（FINISHED）后 `JobManager` 未从内存中清理对应的 `InsertJob` 对象。每次 FE 重启都会重新加载全部历史 job，导致内存持续增长直至 OOM。

## Fix

- **临时止血（紧急）**: 
  ```sql
  -- 找到最老的 FINISHED job
  SHOW LOAD WHERE State='FINISHED' ORDER BY CreateTime LIMIT 1;
  ```
  如果版本支持 `DROP LOAD` 清理历史 job（谨慎操作，仅对不再需要审计的 job）

- **临时止血（代码层面）**: FE 代码增加 `JobManager.cleanFinishedJobs()` 清理逻辑，定期清理 memory 中的已完成 job

- **根治**: 
  1. `JobManager` 对 FINISHED job 执行即时清理
  2. Reload 时增加 max job count 保护，超出阈值时只加载最近 N 个
  3. 为历史 job 增加 TTL，超时自动清理元数据和内存

## Key diagnostic actions

1. `SHOW LOAD` / `SHOW INSERT` 统计历史 job 总数
2. `jmap -histo` 确认 InsertJob/AbstractJob 对象数量
3. `jmap -heap` 确认 Old Gen 使用率
4. fe.log 搜索 `OOM` / `GC overhead` / `heap space` 确认 OOM 时间线
5. 确认 FE restart 后 job 数量是否同样上升（验证 reload 逻辑）
