---
type: reference
category: node
keywords: [file_cache, LRU, memory leak, heap dump, jeprof, MEM_LIMIT_EXCEEDED]
---

# Case-002: File Cache LRU Recorder Queue Pileup Causing BE Memory Leak

## Environment

- Doris version: 4.1.2 (cloud)
- Architecture: storage-compute separation

## Symptom

BE RSS grows linearly and is never released, even with no queries running. Eventually triggers `MEM_LIMIT_EXCEEDED`.
CPU also rises while memory grows. DataPageCache and SegmentCache metrics look normal (low watermark).

## Key evidence

Heap dump analysis shows the memory increase is mainly in:
```
LRUQueueRecorder::record_queue_event
  → moodycamel::ConcurrentQueue<CacheLRULog>
```

In `/profile`:
```
VmRSS: 228.56 GB
DataPageCache Current: 410.65 MB    ← not the culprit
SegmentCache Current: 0             ← not the culprit
QueryCache@cache Current: 45.56 GB  ← the largest consumer but not the leak source
```

`CacheMemory: 45.95 GB` mostly comes from QueryCache, while the bulk of the heap dump increase is the FileCache LRU recorder queue.

## Investigation

### Step 1: Rule out DataPageCache/SegmentCache

Metrics show the abnormal BE's DataPageCache (410MB) and SegmentCache (0) are far below those of other BEs — ruled out.

### Step 2: Locate via heap dump

`jeprof --text` shows the hotspot at:
```
LRUQueueRecorder::record_queue_event
moodycamel::ConcurrentQueue<CacheLRULog>::enqueue
```

This is the FileCache LRU eviction recorder queue (not the DataPageCache data cache).

### Step 3: Code inspection

In 4.1.2, `file_cache_background_lru_log_replay_interval_ms` defaults to `1000` (consumed once per second), but there is no hard cap on the LRU recorder queue size.

When FileCache access frequency is extremely high, LRU log production rate > consumption rate (once every 1000ms), so the queue piles up indefinitely → heap keeps growing.

### Step 4: Confirm the fixed version

4.1.8 includes the fix (cherry-picked apache/doris PR #64381):
- Adds `file_cache_background_lru_log_queue_max_size=500000`
- Changes the default of `file_cache_background_lru_log_replay_interval_ms` from `1000` to `1`
- Adds accounting/release logic for the LRU recorder queue size

## Root Cause

Under high-frequency access, the FileCache LRU recorder queue produces faster than it consumes, and 4.1.2 has no queue size hard cap, so the queue piles up without bound → BE heap keeps growing.

## Fix

- **Temporary workaround**: Lower `file_cache_background_lru_log_replay_interval_ms` (1000→1 or 100) to increase consumption frequency. Note: already-accumulated memory is not returned immediately
  ```bash
  curl -X POST "http://<be>:8040/api/update_config?file_cache_background_lru_log_replay_interval_ms=1&persist=true"
  ```
- **Stop the bleeding**: Restart the affected BEs to release the piled-up recorder queue memory
- **Permanent fix**: Upgrade to 4.1.8 or backport PR #64381 (adds queue size hard cap)

## Key diagnostic actions

1. `jeprof --text` heap dump → confirm the hotspot is `LRUQueueRecorder`
2. `be-metrics --grep file_cache` → watch `file_cache_need_update_lru_blocks_length`
3. If RSS stays high after ruling out DataPageCache/SegmentCache/QueryCache → suspect FileCache LRU
4. Check the current value of `file_cache_background_lru_log_replay_interval_ms`
