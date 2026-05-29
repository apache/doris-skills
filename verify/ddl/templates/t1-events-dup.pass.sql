-- ref: doris-best-practices/SKILL.md:110 (T1 append-only events, DUPLICATE)
-- desc: T1 DUPLICATE events template must be accepted
-- min_version: 2.1
-- mode: any
CREATE TABLE events (
    entity_id    VARCHAR(64)  NOT NULL,
    event_time   DATETIME     NOT NULL,
    event_type   VARCHAR(50)  NOT NULL,
    payload      VARIANT
) DUPLICATE KEY(entity_id, event_time, event_type)
PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(entity_id) BUCKETS 10
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-90",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "compression" = "zstd",
    "compaction_policy" = "time_series",
    "replication_num" = "1"
);
