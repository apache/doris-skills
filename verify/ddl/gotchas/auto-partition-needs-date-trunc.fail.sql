-- ref: doris-best-practices/SKILL.md:91
-- desc: AUTO PARTITION BY RANGE with a bare column (no date_trunc) must be rejected
-- min_version: 2.1
-- mode: any
-- errlike: auto create partition only support date_trunc
CREATE TABLE t_autopart_nodatetrunc (
    id         BIGINT   NOT NULL,
    event_time DATETIME NOT NULL
) DUPLICATE KEY(id, event_time)
AUTO PARTITION BY RANGE(event_time) ()
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");
