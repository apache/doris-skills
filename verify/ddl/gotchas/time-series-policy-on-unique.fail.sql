-- ref: doris-best-practices/SKILL.md:94
-- desc: compaction_policy="time_series" only for DUPLICATE — must be rejected on UNIQUE
-- min_version: 2.0
-- mode: any
-- errlike: Time series compaction policy is not supported
CREATE TABLE t_tspolicy_uniq (
    id BIGINT   NOT NULL,
    ts DATETIME NOT NULL,
    v  INT
) UNIQUE KEY(id, ts)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "compaction_policy" = "time_series",
    "replication_num" = "1"
);
