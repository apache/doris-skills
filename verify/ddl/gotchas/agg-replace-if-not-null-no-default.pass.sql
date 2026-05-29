-- ref: doris-best-practices/SKILL.md:100
-- desc: AGGREGATE non-string REPLACE_IF_NOT_NULL WITHOUT DEFAULT must be accepted (the documented workaround)
-- min_version: 2.0
-- mode: any
CREATE TABLE t_agg_rinn_ok (
    k         INT NOT NULL,
    vip_level INT REPLACE_IF_NOT_NULL
) AGGREGATE KEY(k)
DISTRIBUTED BY HASH(k) BUCKETS 1
PROPERTIES ("replication_num" = "1");
