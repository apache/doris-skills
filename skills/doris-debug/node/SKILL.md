---
name: doris-debug-node
description: >
  Use for Doris FE/BE OOM, crash, or false Alive. BE: MemTrackerLimiter lines in be.WARNING;
  FE: JVM heap / jstack. Distinguish heartbeat Alive from query/brpc serving health.
version: 0.2.0
category: node
---

# Node Health

## Causes

| ID | Cause | Evidence | Source anchor |
|----|-------|----------|---------------|
| A | BE OOM / killed | `dmesg` shows `Killed`; `be.WARNING` MemTrackerLimiter | `mem_tracker_limiter.cpp` |
| B | FE JVM OOM | GC overhead / heap dump; `fe.out` shows `OutOfMemoryError` | `fe.conf` JVM opts |
| C | BE crash (SIGSEGV/SIGABRT) | Core dump; `be.out` stacktrace | `doris_main.cpp` signal handler |
| D | False Alive | `SHOW BACKENDS` Alive=true but queries fail brpc | `heartbeat` vs brpc health |
| E | FD exhaustion | `Too many open files` in be.WARNING | `ulimit -n` |

## 10 min triage

```bash
# Memory pressure signals
./scripts/doris-debug log-grep be/log --pack memory
dmesg -T | grep -i "killed process" | tail -5

# FE JVM
jstack $(cat /path/to/fe.pid) > /tmp/fe.jstack
jmap -heap $(cat /path/to/fe.pid) 2>/dev/null | head -30

# FD count
ls /proc/$(cat /path/to/be.pid)/fd | wc -l
cat /proc/$(cat /path/to/be.pid)/limits | grep "open files"

# Resource snapshot
top -b -n 1 -p $(cat /path/to/be.pid) | head -5
free -h
```

## Cause A — BE OOM

Doris tracks memory via MemTracker, but process RSS exceeds tracked memory due to:
- jemalloc arena fragmentation (10-20% overhead)
- brpc buffer pools (outside MemTracker)
- Thread stacks (~8MB each × thread count)

```bash
# RSS vs tracked
ps -o rss= -p $BE_PID | awk '{printf "RSS: %.1f GB\n", $1/1024/1024}'
grep "MemTrackerLimiter.*total" be/log/be.WARNING | tail -1
```

```properties
# be.conf — defensive settings
mem_limit = 70%              # Leave 30% for overhead
max_segment_cache_size = 0   # Or cap explicitly
enable_je_purge = true       # jemalloc dirty page cleanup
```

If `ProcessMemoryReachedCancel` didn't fire but OOM killer did: the gap between mem_limit and system RAM wasn't enough for jemalloc + brpc overhead.

## Cause B — FE JVM

```bash
# FE JVM opts (from fe.conf or start script)
ps aux | grep "PaloFe" | grep -o "\-Xmx[^ ]*"
```

Common: FE heap grows with catalog metadata (many tables/partitions). Raise `-Xmx` or reduce `hive_meta_cache_ttl_sec` / catalog refresh frequency.

## Cause D — False Alive

Alive=true means the heartbeat RPC succeeds. This does NOT mean the brpc port (8060) is healthy for data transfer. If queries fail with E1008 while Alive=true:

→ Route to **doris-debug-query** (Cause D — Exchange / brpc)
→ Check `priority_networks`, `enable_brpc_connection_check`, `reset_rpc_channel`
→ Do not trust `SHOW BACKENDS` Alive alone

## Source

- `be/src/runtime/memory/mem_tracker_limiter.cpp`
- `be/src/service/doris_main.cpp` — jemalloc init, signal handler
- `fe/.../master/HeartbeatHandler.java`
- `be/src/common/config.cpp` — `mem_limit`, `enable_je_purge`, `max_segment_cache_size`
