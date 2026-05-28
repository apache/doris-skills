---
title: Inverted Index for Text Search and Range on Non-Key Columns
impact: HIGH
tags: [schema, index, inverted, text-search, range]
---
## Inverted Index for Text Search and Range on Non-Key Columns
**Impact: HIGH — Enables full-text search and efficient range filters without modifying the sort key.**
```sql
-- Text search with parser
INDEX idx_body(body) USING INVERTED PROPERTIES("parser" = "unicode")
-- Equality/range on non-key column
INDEX idx_status(status) USING INVERTED
```
**Parser options:** `none` (exact), `english`, `unicode` (multilingual), `chinese` (CJK).
**Supported filter types:** `=`, `IN`, `>`, `<`, `>=`, `<=`, `MATCH_ALL`, `MATCH_ANY`, `MATCH_PHRASE`.
Reference: [Inverted Index](https://doris.apache.org/docs/table-design/index/inverted-index)
