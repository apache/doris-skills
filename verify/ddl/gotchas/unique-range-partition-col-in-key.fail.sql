-- ref: doris-best-practices/SKILL.md:88
-- desc: UNIQUE + PARTITION BY RANGE — partition column NOT in UNIQUE KEY must be rejected
-- min_version: 2.0
-- mode: any
-- errlike: partition column must be KEY column
CREATE TABLE t_uniq_part_bad (
    id BIGINT   NOT NULL,
    dt DATETIME NOT NULL,
    v  INT
) UNIQUE KEY(id)
PARTITION BY RANGE(dt) (PARTITION p1 VALUES LESS THAN ("2025-01-01"))
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("enable_unique_key_merge_on_write" = "true", "replication_num" = "1");
