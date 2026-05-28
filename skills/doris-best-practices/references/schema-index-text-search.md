---
title: Full-Text Search with MATCH Functions
impact: HIGH
tags: [schema, index, text-search, match, search, bm25, inverted]
---
## Full-Text Search with MATCH Functions and BM25 Scoring
**Impact: HIGH — Enables search-engine-like text queries with relevance ranking.**
**7 MATCH operators:** MATCH_ALL, MATCH_ANY, MATCH_PHRASE, MATCH_PHRASE_PREFIX, MATCH_PHRASE_EDGE, MATCH_REGEXP, MATCH_ELEMENT_EQ.
```sql
-- Setup: Inverted index with parser
INDEX idx_content(content) USING INVERTED PROPERTIES(
    "parser" = "unicode", "support_phrase" = "true"
)
-- Queries (WHERE clause only):
WHERE content MATCH_ALL 'database analytics'    -- all terms
WHERE content MATCH_ANY 'database analytics'    -- any term
WHERE content MATCH_PHRASE 'real time analytics' -- exact phrase
```
**SEARCH() unified DSL:** Combine operators in one function:
```sql
WHERE SEARCH(content, '"real time" +analytics -legacy', 'parser=unicode')
```
**BM25 scoring:** Rank results by relevance:
```sql
SELECT doc_id, score() AS relevance FROM docs
WHERE content MATCH_ANY 'doris analytics' ORDER BY relevance DESC;
```
**Custom analyzers, hybrid text+vector search, and VARIANT text search** are all supported.
Reference: [Full-Text Search](https://doris.apache.org/docs/table-design/index/inverted-index)
