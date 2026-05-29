-- ref: doris-best-practices/SKILL.md:190 (T5 point query / API serving, UNIQUE MoW + row store)
-- desc: T5 UNIQUE MoW with store_row_column=true must be accepted
-- min_version: 2.1
-- mode: any
CREATE TABLE user_profiles (
    user_id      BIGINT       NOT NULL,
    update_time  DATETIME     NOT NULL,
    name         VARCHAR(100),
    data         VARIANT
) UNIQUE KEY(user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 5
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time",
    "store_row_column" = "true",
    "light_schema_change" = "true",
    "replication_num" = "1"
);
