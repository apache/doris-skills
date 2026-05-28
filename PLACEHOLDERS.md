# Placeholders

The shared skills under `skills/` contain 5 placeholder tokens. Brand repositories supply concrete values via `brand.values.yaml` and use `scripts/render.sh` to produce final skill content.

## Tokens

| Placeholder | Type | Example (VeloDB) | Example (SelectDB) | Used in |
|---|---|---|---|---|
| `{{CLI}}` | string | `velocli` | `sdbcli` | All shared skills that mention CLI commands |
| `{{CLI_PATH_ENV}}` | string | `VELOCLI_PATH` | `SDBCLI_PATH` | CLI binary detection in `doris-best-practices/SKILL.md` and `cli-investigation.md` |
| `{{PRODUCT_NAME}}` | string | `VeloDB` | `SelectDB` | Product-name references in narrative text and customer-story examples |
| `{{CLOUD_PRODUCT_NAME}}` | string | `VeloDB Cloud` | `SelectDB Cloud` | Cloud-product-specific behavior (e.g., "managed by … automatically") |
| `{{CLOUD_OPS_SKILL}}` | string | `velodb-cloud` | `selectdb-cloud` | Skill-name cross-references to the brand's Cloud operations skill |

## Versioning

This file is the contract between the shared repo and brand repos. If a placeholder is added, renamed, or removed:

1. Bump shared repo to a new git tag (semver MINOR for additions, MAJOR for renames/removals)
2. Update this file's version history below
3. Brand repos must update their `brand.values.yaml` to match before pulling the new shared version

## Version history

- **1.0** (initial) — `{{CLI}}`, `{{CLI_PATH_ENV}}`, `{{PRODUCT_NAME}}`, `{{CLOUD_PRODUCT_NAME}}`, `{{CLOUD_OPS_SKILL}}`

## Banned bare strings (CI enforcement)

`scripts/lint-no-brand.sh` rejects any of these literal strings appearing in `skills/**/*.md`:

- `velocli`, `sdbcli`, `VELOCLI`, `SDBCLI`
- `VeloDB`, `SelectDB`
- `velodb.cloud`, `velodb.io`, `selectdb.com`, `selectdb.cn`
- `~/.velodb`, `~/.selectdb`
- `VELO_`, `SDB_` (as env-var prefixes — full identifiers like `$VELO_HOST`)

These should all be expressed via placeholders or neutralized to "Apache Doris" / "Cloud mode".
