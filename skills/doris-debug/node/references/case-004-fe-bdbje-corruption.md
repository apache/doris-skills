---
type: reference
category: node
keywords: [FE, BDBJE, startup failure, metadata corruption, .jdb, doris-meta, recovery]
---

# Case-004: FE BDBJE Metadata Corruption Preventing Startup

## Environment

- Doris version: all versions (BDBJE-based FE)
- Architecture: shared-nothing / cloud

## Symptom

FE exits on startup; fe.log shows:
```
java.io.FileNotFoundException: doris-meta/bdb/0000014d.jdb
  (No such file or directory)
```
or:
```
com.sleepycat.je.EnvironmentFailureException: ... Environment must be closed ...
java.lang.IllegalStateException: Environment is invalid
```

The FE process exits automatically a few seconds after startup. `SHOW FRONTENDS` on other nodes shows this FE's status as `UNKNOWN` or heartbeat timeout.

## Investigation

### Step 1: Check filesystem state

```bash
ls -la fe/doris-meta/bdb/
# Review the .jdb file list to confirm which files are missing

du -sh fe/doris-meta/bdb/
# Check whether the directory size is abnormally small (< normal size = possibly wiped or corrupted)

df -h fe/doris-meta/
# Check whether the disk was ever full
```

Common scenarios:
- Disk filled up → BDBJE write failed → log files incomplete or missing
- Abnormal shutdown (kill -9 / power loss) → BDBJE did not finish checkpoint → log files corrupted
- Files in `doris-meta/bdb/` deleted by human error

### Step 2: Check cluster state

```sql
-- Execute on another healthy FE
SHOW FRONTENDS\G
```

Confirm:
- Is there still a healthy Master/Follower?
- What is the role of the failed FE (Master / Follower / Observer)?

**Key principle: NEVER delete the doris-meta/ directory of the last healthy Master.**

### Step 3: Recovery strategy

#### Scenario A: The failed FE is a Follower or Observer

```
1. Remove the FE from the cluster:
   ALTER SYSTEM DROP FOLLOWER "bad_host:9010"
   or ALTER SYSTEM DROP OBSERVER "bad_host:9010"

2. Stop the FE process

3. Clear doris-meta/:
   rm -rf fe/doris-meta/*

4. Rejoin the cluster:
   ALTER SYSTEM ADD FOLLOWER "bad_host:9010"
   # The FE will automatically sync metadata from the Master
```

#### Scenario B: The failed FE is the Master but other healthy Followers exist

```
1. Remove the Master from the cluster (the cluster will automatically re-elect)
2. Clear that FE's doris-meta/
3. Rejoin as a Follower
```

#### Scenario C: The failed FE is the only Master with no Followers

```
⚠️ Highest-risk scenario
1. Back up the entire fe/doris-meta/ directory first
2. Attempt BDBJE recovery:
   java -jar je.jar DbRecover -h fe/doris-meta/bdb
3. If recovery fails, use the most recent metadata image:
   the latest image file under fe/doris-meta/image/
4. Contact professional support
```

## Root Cause

BDBJE log files (.jdb) were corrupted or lost due to a full disk, abnormal shutdown, or human error.

## Fix

- **Recover from a healthy replica**: If a healthy Follower/Observer exists, rsync `doris-meta/` from it
- **BDBJE recovery**: Use the Berkeley DB JE recovery tool (success rate depends on the extent of corruption)
- **Prevention**:
  1. Monitor FE disk usage and reserve ample space
  2. Configure at least 1 Follower + 1 Observer for high availability
  3. Back up `fe/doris-meta/` regularly
  4. Use graceful shutdown (`kill -15` instead of `kill -9`)

## Key diagnostic actions

1. `ls -la fe/doris-meta/bdb/` to confirm file integrity
2. `SHOW FRONTENDS` to see which nodes in the cluster are still healthy
3. Confirm the role of the corrupted FE (Master/Follower/Observer)
4. NEVER delete the `doris-meta/` of the last healthy Master
5. Back up the existing `doris-meta/` before attempting recovery
