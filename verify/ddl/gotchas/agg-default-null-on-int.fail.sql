-- ref: doris-best-practices/SKILL.md:100
-- desc: AGGREGATE DEFAULT "null" works only for VARCHAR — on INT it must be rejected
-- min_version: 2.0
-- mode: any
-- errlike: Invalid number format: null
CREATE TABLE t_agg_defnull_int (
    k         INT NOT NULL,
    vip_level INT REPLACE_IF_NOT_NULL DEFAULT "null"
) AGGREGATE KEY(k)
DISTRIBUTED BY HASH(k) BUCKETS 1
PROPERTIES ("replication_num" = "1");
