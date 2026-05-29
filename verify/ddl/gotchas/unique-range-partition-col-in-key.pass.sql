-- ref: doris-best-practices/SKILL.md:88
-- desc: UNIQUE + PARTITION BY RANGE — partition column IN the UNIQUE KEY must be accepted
-- min_version: 2.0
-- mode: any
CREATE TABLE t_uniq_part_good (
    id BIGINT   NOT NULL,
    dt DATETIME NOT NULL,
    v  INT
) UNIQUE KEY(id, dt)
PARTITION BY RANGE(dt) (PARTITION p1 VALUES LESS THAN ("2025-01-01"))
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("enable_unique_key_merge_on_write" = "true", "replication_num" = "1");
