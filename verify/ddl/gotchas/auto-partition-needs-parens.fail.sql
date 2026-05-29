-- ref: doris-best-practices/SKILL.md:91
-- desc: AUTO PARTITION BY RANGE(date_trunc(...)) WITHOUT trailing empty parens () must be rejected
-- min_version: 2.1
-- mode: any
-- errlike: mismatched input 'DISTRIBUTED' expecting '('
CREATE TABLE t_autopart_noparens (
    id         BIGINT   NOT NULL,
    event_time DATETIME NOT NULL
) DUPLICATE KEY(id, event_time)
AUTO PARTITION BY RANGE(date_trunc(event_time, 'day'))
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");
