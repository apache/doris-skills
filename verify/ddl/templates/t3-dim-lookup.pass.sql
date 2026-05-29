-- ref: doris-best-practices/SKILL.md:155 (T3 small dimension / lookup, UNIQUE)
-- desc: T3 small UNIQUE dimension (no partition, 3 buckets) must be accepted
-- min_version: 2.0
-- mode: any
CREATE TABLE dim_product (
    product_id   INT          NOT NULL,
    name         VARCHAR(200),
    category     VARCHAR(50)
) UNIQUE KEY(product_id)
DISTRIBUTED BY HASH(product_id) BUCKETS 3
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "replication_num" = "1"
);
