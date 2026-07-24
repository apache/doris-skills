---
type: reference
category: node
keywords: [file_cache, LRU, memory leak, heap dump, jeprof, MEM_LIMIT_EXCEEDED]
---

# Case-002: File Cache LRU Recorder 队列堆积导致 BE 内存泄漏

## Environment

- Doris version: 4.1.2 (cloud)
- Architecture: storage-compute separation

## Symptom

BE RSS 持续线性增长，无查询时也不释放。最终触发 `MEM_LIMIT_EXCEEDED`。
CPU 在内存上涨期间也升高。DataPageCache 和 SegmentCache 监控显示正常（低水位）。

## Key evidence

heap dump 分析显示内存增量主要落在：
```
LRUQueueRecorder::record_queue_event
  → moodycamel::ConcurrentQueue<CacheLRULog>
```

`/profile` 中：
```
VmRSS: 228.56 GB
DataPageCache Current: 410.65 MB    ← 不是它
SegmentCache Current: 0             ← 不是它
QueryCache@cache Current: 45.56 GB  ← 占大头但不是泄漏源
```

`CacheMemory: 45.95 GB` 主要来自 QueryCache，而 heap dump 增量大头是 FileCache LRU recorder 队列。

## Investigation

### Step 1: 排除 DataPageCache/SegmentCache

监控显示异常 BE 的 DataPageCache（410MB）和 SegmentCache（0）远低于其他 BE，排除。

### Step 2: heap dump 定位

`jeprof --text` 显示热点在：
```
LRUQueueRecorder::record_queue_event
moodycamel::ConcurrentQueue<CacheLRULog>::enqueue
```

这是 FileCache 的 LRU 淘汰记录队列（不是 DataPageCache 的数据缓存）。

### Step 3: 代码核对

4.1.2 版本中，`file_cache_background_lru_log_replay_interval_ms` 默认为 `1000`（1 秒消费一次），但没有 hard cap 限制 LRU recorder queue 的大小。

当 FileCache 访问频率极高时，LRU log 的生产速度 > 消费速度（1000ms 一次），队列无限堆积 → heap 持续上涨。

### Step 4: 修复版本确认

4.1.8 版本已引入修复（cherry-pick apache/doris PR #64381）：
- 新增 `file_cache_background_lru_log_queue_max_size=500000`
- `file_cache_background_lru_log_replay_interval_ms` 默认从 `1000` 改为 `1`
- 增加 LRU recorder queue size 的计数/释放逻辑

## Root Cause

FileCache 的 LRU recorder queue 在高频访问下生产速度超过消费速度，且 4.1.2 版本中没有 queue size hard cap，导致 queue 无限堆积 → BE heap 持续增长。

## Fix

- **临时规避**: 调小 `file_cache_background_lru_log_replay_interval_ms`（1000→1 或 100），提高消费频率。但已堆积的内存不会立即归还
  ```bash
  curl -X POST "http://<be>:8040/api/update_config?file_cache_background_lru_log_replay_interval_ms=1&persist=true"
  ```
- **止血**: 重启受影响 BE 释放已堆积的 recorder queue 内存
- **根治**: 升级到 4.1.8 或 backport PR #64381（增加 queue size hard cap）

## Key diagnostic actions

1. `jeprof --text` heap dump → 确认热点在 `LRUQueueRecorder`
2. `be-metrics --grep file_cache` → 观察 `file_cache_need_update_lru_blocks_length`
3. 排除 DataPageCache/SegmentCache/QueryCache 后仍高 RSS → FileCache LRU
4. 检查 `file_cache_background_lru_log_replay_interval_ms` 当前值
