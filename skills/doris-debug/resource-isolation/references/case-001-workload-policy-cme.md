---
type: reference
category: resource-isolation
keywords: [ConcurrentModificationException, session variable, one-shot, setVarOnce, workload policy, HashMap concurrent]
---

# Case-001: Intermittent ConcurrentModificationException in Queries — Session Variable One-Shot Rollback Exception

## Environment

- Doris version: 4.1.7 (cloud)
- Architecture: storage-compute separation
- Nereids optimizer enabled

## Symptom

Queries intermittently throw `java.util.ConcurrentModificationException`. The probability is low but the blast radius is large.

Key observation: the SQL has actually finished executing (`Query finished` was already printed, `ReturnRows=1`), but the audit State is set to `ERR` and the client sees the exception.

## Key evidence

### FE logs

```
StatsCalculator.disableJoinReorderIfStatsInvalid():
  disable join reorder since row count not available:
  internal.data_warehouse_dws.mv_freshness_bet_overview_account_10m
```

The table's statistics have row_count=0, triggering Nereids `setVarOnce(disable_join_reorder=true)`.

```
Query ... finished. ReturnRows=1, Time(ms)=6, ScanRows=0
```

The SQL has finished executing.

```
java.util.ConcurrentModificationException
  at java.base/java.util.HashMap$HashIterator.nextNode(HashMap.java)
  at java.base/java.util.HashMap$EntryIterator.next(HashMap.java)
  at java.base/java.util.HashMap$EntryIterator.next(HashMap.java)
  at VariableMgr.revertSessionValue()
```

A HashMap concurrent modification error occurs while rolling back session variables in the finally block.

## Investigation

### Step 1: Confirm the CME trigger path

1. The scanned table has `row_count=-1` (statistics unavailable)
2. `StatsCalculator.disableJoinReorderIfStatsInvalid()` calls `SessionVariable.setVarOnce(disable_join_reorder=true)`
3. `setVarOnce()` writes the original value into `sessionOriginValue` (a `HashMap`)
4. After the SQL finishes, `StmtExecutor.execute()`'s finally block calls `VariableMgr.revertSessionValue()`
5. `revertSessionValue()` directly iterates the live keySet of `sessionOriginValue.keySet()`
6. While iterating, the same `SessionVariable`'s `sessionOriginValue` is concurrently written/cleared by another path → `HashMap` fail-fast → CME

### Step 2: Code verification (4.1.7)

```java
// SessionVariable.java
public Map<SessionVariableField, String> sessionOriginValue = new HashMap<>();

// VariableMgr.java
public static void revertSessionValue(SessionVariable obj) {
    Map<SessionVariableField, String> sessionOriginValue = obj.getSessionOriginValue();
    if (!sessionOriginValue.isEmpty()) {
        for (SessionVariableField field : sessionOriginValue.keySet()) {
            // directly iterates the live HashMap keySet; no snapshot, no lock
            setValue(obj, field, sessionOriginValue.get(field));
        }
    }
}
```

### Step 3: Blast radius

Not limited to the Nereids statistics path. All `setVarOnce` paths (runtime filter wait time, auto analyze, etc.) share the same risk surface.

### Step 4: Related history

There is a historical fix `apache/doris#48239` (ExportTaskExecutor clone SessionVariable), but it only covers the Export scenario, not the normal SELECT `StmtExecutor → revertSessionValue` path.

## Root Cause

`VariableMgr.revertSessionValue()` directly iterates the live `HashMap.keySet()` (no snapshot, no lock). When `sessionOriginValue` is concurrently modified by another path during iteration, the `HashMap` iterator's fail-fast behavior throws a CME.

Trigger condition: the Nereids optimizer calls `setVarOnce(disable_join_reorder=true)` because statistics are unavailable, and `sessionOriginValue` is then concurrently modified during the finally rollback.

## Fix

- **Short-term workaround**: Manually run `ANALYZE TABLE` on the involved tables to collect statistics, avoiding the `row_count=-1 → setVarOnce` path. This only avoids the current trigger point; it does not fix the underlying bug.
- **Code fix**:
  1. In `VariableMgr.revertSessionValue()`, snapshot the `entrySet` before iterating (`new ArrayList<>(sessionOriginValue.entrySet())`)
  2. Add synchronization boundaries around reads/writes of `sessionOriginValue`
  3. Execute `setIsSingleSetVar(false) / clearSessionOriginValue()` in a finally block to avoid residue after exceptions
- **State fix**: `StmtExecutor`'s finally block currently only catches `DdlException`; cleanup exceptions should be guarded so they do not overwrite the state of an already-successful query

## Key diagnostic actions

1. Search fe.log for `ConcurrentModificationException` → confirm the stack is in `revertSessionValue`
2. Confirm whether the same connection is used concurrently by multiple threads (accelerates CME exposure)
3. Check `SHOW TABLE STATS` to confirm whether row_count is normal
4. Use `ANALYZE TABLE` as a temporary workaround (only avoids the statistics path; does not fix the root cause)
