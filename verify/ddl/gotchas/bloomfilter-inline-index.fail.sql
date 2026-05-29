-- ref: doris-best-practices/SKILL.md:98
-- desc: BloomFilter must go via PROPERTIES bloom_filter_columns — inline INDEX ... USING BLOOM FILTER must be rejected
-- min_version: 2.0
-- mode: any
-- errlike: mismatched input 'BLOOM'
CREATE TABLE t_bf_inline (
    id   BIGINT       NOT NULL,
    name VARCHAR(50),
    INDEX idx_name (name) USING BLOOM FILTER
) DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");
