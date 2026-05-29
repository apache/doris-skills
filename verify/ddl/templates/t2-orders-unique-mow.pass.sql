-- ref: doris-best-practices/SKILL.md:132 (T2 updatable UNIQUE MoW + CDC)
-- desc: T2 UNIQUE MoW + sequence_col + dynamic partition template must be accepted
-- min_version: 2.0
-- mode: any
CREATE TABLE orders (
    order_id     BIGINT       NOT NULL,
    order_time   DATETIME     NOT NULL,
    update_time  DATETIME     NOT NULL,
    status       VARCHAR(20),
    amount       DECIMAL(18,2)
) UNIQUE KEY(order_id, order_time)
PARTITION BY RANGE(order_time) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 5
PROPERTIES (
    "enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "1"
);
