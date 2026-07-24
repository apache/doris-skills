# Case: Cumulative compaction can't keep up with high-frequency ingest

## Symptom

`-235` (TOO_MANY_VERSION) on Stream Load / INSERT. `SHOW PROC '/cluster_health/tablet_health'` shows many tablets near `max_tablet_version_num` (default 2000). Compaction metrics show cumulative compaction queued but score rising.

## Root cause

Ingest rate (version creation) > cumulative compaction throughput. This is NOT a compaction speed problem — it's a compaction trigger / scheduling problem. Compaction_score grows until tablet version_count hits the hard cap.

## Fix direction

1. Check `be/log/be.INFO` for `"reach version limit"` lines
2. `log-grep --pack versions` to confirm affected tablets
3. Raise `max_tablet_version_num` to **unblock writes immediately** (symptom relief)
4. Then fix the root cause:
   - Reduce ingest frequency: increase group commit `interval_ms` / `data_bytes`
   - Increase compaction thread pool: `max_cumulative_compaction_threads` / `compaction_task_num_per_disk`
   - Check disk IO: `iostat -x 1` — if disk util > 90%, compaction can't catch up regardless of thread count
5. For time-series workloads, set `time_series_max_tablet_version_num` separately

Source: `rowset_builder.cpp` check_tablet_version_count, `compaction_policy.cpp` cumulative score.
