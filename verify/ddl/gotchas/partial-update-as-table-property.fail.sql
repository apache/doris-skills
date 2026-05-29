-- ref: doris-best-practices/SKILL.md:101
-- desc: enable_unique_key_partial_update is a SESSION variable, not a table property — as a property it must be rejected
-- min_version: 2.0
-- mode: any
-- errlike: Unknown properties: {enable_unique_key_partial_update
CREATE TABLE t_partialupd_prop (
    id BIGINT NOT NULL,
    v  INT
) UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "enable_unique_key_partial_update" = "true",
    "replication_num" = "1"
);
