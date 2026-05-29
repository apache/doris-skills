# Example: Retail & Fashion — Omnichannel Operations Platform

## Scenario

- **Workload:** Fashion/sportswear brand with 8,000+ stores, online channels (Tmall, JD, Douyin), and manufacturing (MES/SCM)
- **Data sources:** CRM, ERP, SCM, OA, MES, WMS, POS (store sales), Taobao/JD/Douyin APIs, competitor data, trend data
- **Data volume:** ~100M orders/year, 20M loyalty members, 50M SKU-location inventory records, billions of clickstream events
- **Query patterns:** Real-time store dashboards, inventory monitoring, customer segmentation (BITMAP), product sell-through, promotion ROI, supply chain tracking, financial reporting
- **Special requirements:** ODS→DWD→DWS→ADS layering, wide table + tall table for user profiling, multi-brand isolation, peak season scaling (Double 11 / 618)

## Workload Classification

**Composite workload** — 7 sub-workloads:

| Sub-workload | Type | Tables |
|-------------|------|--------|
| Order/transaction data (omnichannel) | CDC sync + Time-series | `ods_orders`, `dwd_orders` |
| Inventory state (real-time) | Mutable state | `inventory_state` |
| Customer profile (wide table) | Mutable state + Point query | `customer_profile_wide` |
| Customer tags (tall table / BITMAP) | Pre-aggregation | `customer_tag_bitmap` |
| Product master + SKU attributes | Dimension | `dim_product`, `dim_store` |
| Store/channel KPI dashboards | Report / Pre-aggregation | `ads_store_daily`, `ads_channel_daily` |
| Promotion campaign analytics | Report + Ad-hoc | `ads_promotion_realtime` |

## Sizing Recommendation

- **Total vCPU:** 64 vCPU total, 3 TB total cache
- **Hot data:** Orders 1 year (~2 TB compressed) + inventory (~10 GB) + profiles (~50 GB) + events (~5 TB compressed)
- **Peak season:** Consider separate compute group for Double 11 real-time dashboards to isolate from batch ETL
- **Storage:** ~10 TB/year compressed in object storage

## Architecture

```
Internal Systems              Ingestion                   Apache Doris (Real-time DW)              Applications
┌─────────────┐                                          ┌─────────────────────────┐
│ CRM         │── Flink CDC ────────────────────────────│ ODS (UNIQUE MoW)         │
│ ERP         │                                          │  ods_orders, ods_members  │
│ SCM         │                                          ├─────────────────────────┤
│ WMS         │                                          │ DWD (UNIQUE/DUPLICATE)   │──→ Store Operations
│ MES         │── Flink CDC ────────────────────────────│  dwd_orders, dwd_inventory│──→ Product Analysis
│ POS (stores)│                                          ├─────────────────────────┤
├─────────────┤                                          │ DWS (DUPLICATE)          │──→ Financial Reports
│ Tmall API   │                                          │  customer_profile_wide   │──→ Member Services
│ JD API      │── Routine Load (Kafka) ────────────────│  inventory_model          │──→ Replenishment
│ Douyin API  │                                          ├─────────────────────────┤
│ Own website │                                          │ ADS (AGGREGATE)          │──→ KPI Dashboards
├─────────────┤                                          │  ads_store_daily         │──→ Promotion Monitor
│ Competitor  │── Broker Load (batch) ─────────────────│  ads_channel_daily        │──→ Management Cockpit
│ Trends      │                                          │  customer_tag_bitmap     │──→ Marketing Campaigns
└─────────────┘                                          └────────┬────────────────┘
                                                                  │
Data Lake (Hive/Iceberg) ─── Multi-Catalog ──────────────────────┘
  Historical archive             (3+ years, federated query)
```

**ODS/DWD table pattern for retail orders (CRITICAL — partition column must be in UNIQUE KEY):**
```sql
-- ODS order table: UNIQUE KEY includes BOTH order_id AND order_time
-- because PARTITION BY RANGE(order_time) requires order_time in the key
CREATE TABLE ods_orders (
    order_id    BIGINT      NOT NULL,
    order_time  DATETIME(3) NOT NULL,  -- MUST be in UNIQUE KEY when used as partition column
    update_time DATETIME(3) NOT NULL,
    ...
) UNIQUE KEY(order_id, order_time)
PARTITION BY RANGE(order_time) ()
DISTRIBUTED BY HASH(order_id) BUCKETS 10
PROPERTIES ("enable_unique_key_merge_on_write" = "true",
    "function_column.sequence_col" = "update_time", "replication_num" = "1");
```

**DWD layer wide tables** (per the PDF architecture):
- Retail wide table
- Member wide table
- Order wide table
- Inventory wide table
- Shipment wide table
- In-transit wide table

**DWS layer models:**
- Inventory model
- Retail model
- Logistics model
- Member model

**ADS layer reports:**
- Store reports, inventory reports, financial reports, member services, promotion services

## Key Design Pattern: Wide Table vs Tall Table for User Profiling

### Wide table (AGGREGATE + REPLACE_IF_NOT_NULL)

One row per user, one column per tag. Best for point queries ("show me user X's full profile") and ad-hoc analysis.

- AGGREGATE KEY with user_id, every tag column uses REPLACE_IF_NOT_NULL
- Partial tag updates: insert only the changed columns, NULLs are ignored
- Schema changes via `light_schema_change` when adding new tags
- Best for: advisor lookups, detailed user drilldowns, wide analytics

### Tall table (AGGREGATE + BITMAP_UNION)

One row per tag value, BITMAP stores user IDs. Best for audience selection ("find users matching criteria A AND B").

- AGGREGATE KEY with (tag_name, tag_value, date)
- BITMAP_UNION stores set of user_ids per tag value
- `bitmap_intersect()` for cross-tag audience intersection
- `bitmap_union()` for audience union
- `bitmap_count()` for audience sizing
- Best for: marketing campaigns, BITMAP audience segmentation, cohort analysis

### When to use which

| Need | Wide table | Tall table |
|------|-----------|-----------|
| "Show me user X's full profile" | Fast (one row read) | Slow (scan all tags) |
| "Find all users where tag A = X AND tag B = Y" | Slow (full table scan) | Fast (BITMAP intersect, sub-second) |
| "How many users match criteria?" | Slow (COUNT with WHERE) | Fast (bitmap_count) |
| Adding new tags | Schema change (light_schema_change) | Just insert new tag rows |
| Tag count > 500 | Schema becomes unwieldy | No schema impact |

**Best practice:** Use BOTH tables. Wide table for user-facing point queries (advisor/CRM lookups), tall table for marketing segmentation. Sync between them via async MV or scheduled ETL.

## Retail-specific Decision Patterns

### Inventory: UNIQUE MoW (not DUPLICATE)
Inventory is mutable — every sale, return, transfer, and receiving changes the quantity. Use UNIQUE KEY on (sku_id, location_id) with sequence_col on update_time.

### Product sell-through tracking
- DWD: detailed sell-through per SKU-store-day (DUPLICATE, append daily snapshots)
- ADS: aggregated sell-through rate = units_sold / units_received, pre-computed in AGGREGATE model
- Alert when sell-through < threshold → trigger markdown decision

### Multi-brand isolation
Use Workload Groups to isolate brand teams:
- Each brand team gets its own workload group (CPU/memory limits)
- Shared data layer (ODS/DWD), brand-specific ADS views
- Prevents one brand's heavy analysis from impacting others

### Peak season (Double 11 / 618)
- Pre-compute ADS tables before the event starts
- Separate compute group for real-time promotion dashboards
- Increase async MV refresh frequency to every 1-2 minutes during peak
- After peak, scale back to normal refresh intervals

### E-commerce multi-platform data
- Each platform (Tmall, JD, Douyin) has different order/product schemas
- Use VARIANT for platform-specific fields that vary
- Standardize common fields (order_id, sku_id, amount, quantity) as typed columns in DWD
- Deduplicate cross-platform orders by customer OneID in DWS

## Decision Provenance

| Decision | Source |
|----------|--------|
| ODS/DWD layering from 16+ source systems | `official` — standard real-time DW pattern |
| UNIQUE MoW for inventory state | `official` — mutable quantity, needs upsert |
| AGGREGATE + REPLACE_IF_NOT_NULL for wide profile | `official` — partial tag updates without full row replace |
| AGGREGATE + BITMAP_UNION for tall tag table | `official` — sub-second audience segmentation |
| Both wide + tall tables | `derived` — wide for point query, tall for BITMAP segmentation |
| VARIANT for multi-platform e-commerce data | `official` — different schemas per platform |
| Workload Groups for multi-brand isolation | `official` — CPU/memory isolation |
| Separate compute group for peak season | `derived` — elastic scaling during Double 11 / 618 |
| Async MV for DWD→DWS→ADS ETL | `official` — replaces Spark/Hive batch processing |
| 64 vCPU / 3 TB cache | `field` — ~75% accuracy; confirm with Apache Doris SA |
