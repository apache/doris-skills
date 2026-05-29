-- ref: doris-best-practices/SKILL.md:98
-- desc: BloomFilter via PROPERTIES bloom_filter_columns (the correct form) must be accepted
-- min_version: 2.0
-- mode: any
CREATE TABLE t_bf_props (
    id   BIGINT       NOT NULL,
    name VARCHAR(50)
) DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "bloom_filter_columns" = "name",
    "replication_num" = "1"
);
