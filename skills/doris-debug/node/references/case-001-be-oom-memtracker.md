# Case: BE OOM from MemTracker — large query spills but limit doesn't fire

## Symptom

BE process killed by OOM killer (`dmesg | grep "Killed"`), but `be.WARNING` shows `MemTrackerLimiter` lines with memory near but not exceeding `mem_limit`. `ProcessMemoryReachedCancel` not triggered.

## Root cause

`mem_limit` controls the Doris-tracked memory, but process RSS includes:
- Jemalloc arena fragmentation (can add 10-20% overhead)
- brpc buffers (outside MemTracker)
- Thread stacks
- Page cache / mmap regions

When `mem_limit = 80%` of system RAM and jemalloc fragments to 95%, the OOM killer fires even though Doris's own tracking thinks it's within limit.

## Fix direction

1. Check actual RSS: `ps -o rss= -p $BE_PID` → convert to GB
2. `dmesg -T | grep -i "killed process"` to confirm OOM kill
3. `log-grep be/log --pack memory` to see last MemTracker snapshot before crash
4. Lower `mem_limit` to 60-70% of system RAM to leave room for overhead
5. Check `max_segment_cache_size` / `chunk_reserved_bytes_limit` — these are outside MemTracker
6. Consider `enable_je_purge = true` (be.conf) for jemalloc dirty page cleanup

Source: `be/src/runtime/memory/mem_tracker_limiter.cpp`, `be/src/service/doris_main.cpp` jemalloc init.
