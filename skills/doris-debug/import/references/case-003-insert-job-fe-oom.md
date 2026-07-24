---
type: reference
category: import
keywords: [INSERT INTO, OOM, JobManager, job leak, FE memory, jmap, mem_leak]
---

# Case-003: Uncleaned INSERT INTO Jobs Cause FE Memory Blowup and Repeated OOM

## Environment

- Doris version: 26.0.3 (cloud)
- Architecture: storage-compute separation

## Symptom

FE memory keeps growing until OOM; a restart recovers it, but OOM recurs after hours or days.

`jmap -histo` shows a large number of live `InsertJob` objects.

`SHOW LOAD` / `SHOW INSERT` shows thousands of historical jobs (all in FINISHED or CANCELLED state), far beyond the normal range.

## Investigation

### Step 1: Confirm the OOM Type

```bash
jmap -heap <fe_pid> | head -20
# Old Gen usage close to 100%, frequent Full GC

jmap -histo <fe_pid> | head -30
# Abnormally high InsertJob / AbstractJob object count
```

### Step 2: Confirm the Job Count

```sql
SHOW LOAD ORDER BY CreateTime DESC LIMIT 100;
-- Large number of INSERT INTO jobs in FINISHED/CANCELLED state

SELECT COUNT(*) FROM information_schema.loads WHERE Type='INSERT';
-- Returns an abnormally large number (thousands or even tens of thousands)
```

### Step 3: Code Review

INSERT INTO job flow:
1. An INSERT INTO statement is registered as a job (containing an `InsertJob` object)
2. After the job finishes, its state becomes FINISHED
3. `JobManager` should remove FINISHED jobs from memory
4. Bug: `JobManager` does not clean up FINISHED jobs
5. On FE restart, `JobManager.reload()` loads all historical jobs from metadata → repeated OOM

```
FE start
  → JobManager.reload()
    → Load all historical INSERT jobs from doris-meta
      → All InsertJob objects enter the heap
        → Thousands accumulate → Old Gen full → Full GC → OOM
```

## Root Cause

After an INSERT INTO job completes (FINISHED), `JobManager` does not remove the corresponding `InsertJob` object from memory. Every FE restart reloads all historical jobs, causing memory to grow continuously until OOM.

## Fix

- **Temporary stopgap (urgent)**:
  ```sql
  -- Find the oldest FINISHED job
  SHOW LOAD WHERE State='FINISHED' ORDER BY CreateTime LIMIT 1;
  ```
  If the version supports `DROP LOAD` to clean up historical jobs (use with caution, only for jobs no longer needed for auditing)

- **Temporary stopgap (code level)**: Add `JobManager.cleanFinishedJobs()` cleanup logic in the FE code to periodically purge completed jobs from memory

- **Permanent fix**:
  1. `JobManager` cleans up FINISHED jobs immediately
  2. Add a max job count safeguard on reload: when the threshold is exceeded, only load the most recent N jobs
  3. Add a TTL for historical jobs so metadata and memory are cleaned up automatically on expiry

## Key diagnostic actions

1. `SHOW LOAD` / `SHOW INSERT` to count total historical jobs
2. `jmap -histo` to confirm the number of InsertJob/AbstractJob objects
3. `jmap -heap` to confirm Old Gen usage
4. Search fe.log for `OOM` / `GC overhead` / `heap space` to establish the OOM timeline
5. Confirm whether the job count rises again after FE restart (validates the reload logic)
