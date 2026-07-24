---
type: reference
category: resource-isolation
keywords: [ConcurrentModificationException, session variable, one-shot, setVarOnce, workload policy, HashMap concurrent]
---

# Case-001: 查询偶发 ConcurrentModificationException — Session Variable One-Shot 回滚异常

## Environment

- Doris version: 4.1.7 (cloud)
- Architecture: storage-compute separation
- Nereids optimizer enabled

## Symptom

查询偶发 `java.util.ConcurrentModificationException`，概率低但影响面大。

关键现象：SQL 实际已执行完成（`Query finished` 已打印，`ReturnRows=1`），但 audit State 被置为 `ERR`，客户端看到异常。

## Key evidence

### FE 日志

```
StatsCalculator.disableJoinReorderIfStatsInvalid():
  disable join reorder since row count not available:
  internal.data_warehouse_dws.mv_freshness_bet_overview_account_10m
```

表统计信息 row_count=0，触发 Nereids `setVarOnce(disable_join_reorder=true)`。

```
Query ... finished. ReturnRows=1, Time(ms)=6, ScanRows=0
```

SQL 已执行完成。

```
java.util.ConcurrentModificationException
  at java.base/java.util.HashMap$HashIterator.nextNode(HashMap.java)
  at java.base/java.util.HashMap$EntryIterator.next(HashMap.java)
  at java.base/java.util.HashMap$EntryIterator.next(HashMap.java)
  at VariableMgr.revertSessionValue()
```

在 finally 回滚 session variable 时 HashMap 并发修改报错。

## Investigation

### Step 1: 确认 CME 触发路径

1. 查询扫描的表 `row_count=-1`（统计信息不可用）
2. `StatsCalculator.disableJoinReorderIfStatsInvalid()` 调用 `SessionVariable.setVarOnce(disable_join_reorder=true)`
3. `setVarOnce()` 把原始值写入 `sessionOriginValue`（`HashMap`）
4. SQL 执行完成后，`StmtExecutor.execute()` finally 调用 `VariableMgr.revertSessionValue()`
5. `revertSessionValue()` 直接遍历 `sessionOriginValue.keySet()` 的 live keySet
6. 同一 `SessionVariable` 的 `sessionOriginValue` 在遍历期间被其他路径并发写入/清理 → `HashMap` fail-fast → CME

### Step 2: 代码核对（4.1.7）

```java
// SessionVariable.java
public Map<SessionVariableField, String> sessionOriginValue = new HashMap<>();

// VariableMgr.java
public static void revertSessionValue(SessionVariable obj) {
    Map<SessionVariableField, String> sessionOriginValue = obj.getSessionOriginValue();
    if (!sessionOriginValue.isEmpty()) {
        for (SessionVariableField field : sessionOriginValue.keySet()) {
            // 直接遍历 live HashMap keySet，无 snapshot，无锁
            setValue(obj, field, sessionOriginValue.get(field));
        }
    }
}
```

### Step 3: 影响范围

不只是 Nereids 统计信息路径。所有 `setVarOnce` 路径（runtime filter wait time、auto analyze 等）都共享同一风险面。

### Step 4: 历史相关

历史有 `apache/doris#48239`（ExportTaskExecutor clone SessionVariable），但只覆盖 Export 场景，不覆盖普通 SELECT 的 `StmtExecutor → revertSessionValue` 路径。

## Root Cause

`VariableMgr.revertSessionValue()` 直接遍历 live `HashMap.keySet()`（无 snapshot、无锁）。当 `sessionOriginValue` 在遍历期间被其他路径并发修改时，`HashMap` iterator fail-fast 抛出 CME。

触发条件：Nereids 优化器因统计信息不可用而 `setVarOnce(disable_join_reorder=true)`，随后在 finally 回滚时 `sessionOriginValue` 被并发修改。

## Fix

- **短期规避**: 手动对涉及表执行 `ANALYZE TABLE` 收集统计信息，避免触发 `row_count=-1 → setVarOnce` 路径。但这只能规避当前触发点，不修复底层 bug。
- **代码修复**:
  1. `VariableMgr.revertSessionValue()` 先 snapshot `entrySet` 再遍历（`new ArrayList<>(sessionOriginValue.entrySet())`）
  2. 对 `sessionOriginValue` 的读写加同步边界
  3. `setIsSingleSetVar(false) / clearSessionOriginValue()` 在 finally 中执行，避免异常后残留
- **状态修复**: `StmtExecutor` finally 当前只 catch `DdlException`，应保护 cleanup 异常避免覆盖已成功完成的查询状态

## Key diagnostic actions

1. fe.log 搜索 `ConcurrentModificationException` → 确认栈在 `revertSessionValue`
2. 确认同一连接是否多线程并发使用（加速 CME 暴露）
3. 查看 `SHOW TABLE STATS` 确认 row_count 是否正常
4. `ANALYZE TABLE` 作为临时规避（仅规避统计信息路径，不修复根因）
