-- ref: doris-best-practices/SKILL.md:92
-- desc: dynamic_partition.* properties WITHOUT a PARTITION BY clause must be rejected
-- min_version: 2.0
-- mode: any
-- errlike: Only support dynamic partition properties on range partition table
CREATE TABLE t_dynpart_noclause (
    id BIGINT   NOT NULL,
    dt DATETIME NOT NULL
) DUPLICATE KEY(id, dt)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-7",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "1"
);
