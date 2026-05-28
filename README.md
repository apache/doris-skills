# doris-skills

Brand-neutral Apache Doris agent skills for use with Claude Code. This repository contains the **kernel knowledge** that is identical across VeloDB and SelectDB (both built on Apache Doris): table design, sizing, query investigation, and architecture decisions.

Cloud-platform operations (CLI auth, cluster lifecycle, billing, networking) are **brand-specific** and live in separate brand repositories that consume this shared content via a render step.

## Skills

| Skill | Description |
|---|---|
| `doris-best-practices` | Apache Doris table design, sizing, and runtime query investigation (37 rules, 7 use-case templates, 4 sizing guides) |
| `doris-architecture-advisor` | Workload-aware architecture design (8 decision rules, 10 worked industry examples) |

## How brand repositories consume this

Brand repositories (e.g. `velodb-cloud-skills`, `selectdb-cloud-skills`) include this repo as a git submodule and run `scripts/render.sh` at install time:

```bash
# In a brand repo:
./doris-skills/scripts/render.sh ./brand.values.yaml ~/.claude/skills/
```

`render.sh` substitutes the 5 placeholder tokens (see [PLACEHOLDERS.md](PLACEHOLDERS.md)) with brand-specific values and writes rendered skills to the target directory.

## Authoring rules

- **Never** write brand-specific bare strings (CLI names, hostnames, console URLs, env-var prefixes). Use the placeholders in [PLACEHOLDERS.md](PLACEHOLDERS.md), or neutral wording ("Apache Doris" / "Cloud mode").
- Cloud-mode behavior (storage-compute separation, replication_num=1, file cache) is **Doris kernel architecture** — describe it neutrally without naming a specific Cloud product, unless the statement is specifically about brand-managed behavior (e.g., automatic node-count management).
- Run `scripts/lint-no-brand.sh` before committing.

## Layout

```
doris-skills/
├── README.md
├── PLACEHOLDERS.md          # Placeholder catalog + version contract
├── scripts/
│   ├── render.sh            # Substitutes placeholders for a brand
│   └── lint-no-brand.sh     # Fails CI if bare brand strings appear
└── skills/
    ├── doris-best-practices/
    └── doris-architecture-advisor/
```

## License

Apache-2.0
