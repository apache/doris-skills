-- ref: doris-best-practices/SKILL.md:89
-- desc: key columns must be the FIRST N columns — a non-key column between key columns must be rejected
-- min_version: 2.0
-- mode: any
-- errlike: Key columns should be a ordered prefix of the schema
CREATE TABLE t_keyorder_bad (
    account_id BIGINT      NOT NULL,
    name       VARCHAR(50),
    symbol     VARCHAR(20) NOT NULL,
    qty        INT
) UNIQUE KEY(account_id, symbol)
DISTRIBUTED BY HASH(account_id) BUCKETS 1
PROPERTIES ("enable_unique_key_merge_on_write" = "true", "replication_num" = "1");
