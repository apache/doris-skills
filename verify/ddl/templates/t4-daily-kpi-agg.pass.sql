-- ref: doris-best-practices/SKILL.md:169 (T4 pre-aggregated KPIs, AGGREGATE)
-- desc: T4 AGGREGATE template (SUM/MAX/BITMAP_UNION, agg-fn-before-default) must be accepted
-- min_version: 2.0
-- mode: any
CREATE TABLE daily_kpi (
    stat_date    DATE         NOT NULL,
    dimension    VARCHAR(50)  NOT NULL,
    metric_sum   BIGINT       SUM DEFAULT "0",
    metric_max   DOUBLE       MAX DEFAULT "0",
    unique_users BITMAP       BITMAP_UNION
) AGGREGATE KEY(stat_date, dimension)
PARTITION BY RANGE(stat_date) ()
DISTRIBUTED BY HASH(dimension) BUCKETS 3
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "MONTH",
    "dynamic_partition.start" = "-12",
    "dynamic_partition.end" = "1",
    "dynamic_partition.prefix" = "p",
    "replication_num" = "1"
);
