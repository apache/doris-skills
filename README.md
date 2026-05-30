# Agent Skills for Apache Doris

Apache Doris agent skills in the open Agent Skills (`SKILL.md`) format — usable by
Claude Code, Cursor, Codex, Cline, Amp, and other agent tools. This repository contains the
**kernel knowledge** for any Apache Doris deployment: table design, sizing, query
investigation, and architecture decisions.

The skills pair with **`doriscli`**, the Apache Doris CLI (companion `doris-cli`
repository). doriscli is the "hands" — it runs SQL, fetches and parses query profiles,
and analyzes tablet distribution, all as structured JSON; these skills are the "brain" —
the decision logic that reads that JSON and recommends table designs, sizing, and fixes.
doriscli is optional: when it is not installed the skills fall back to plain
MySQL-protocol SQL plus the FE HTTP API, so they work with or without it (see
`skills/doris-best-practices/references/cli-investigation.md`).

The exact doriscli commands and JSON fields the skills depend on are listed in
[CLI-CONTRACT.md](CLI-CONTRACT.md) — keep that file and doriscli in sync.

Cluster-lifecycle, billing, and networking operations are managed-service specific and
intentionally out of scope here; use your platform's cluster-management console for those.

## Skills

| Skill | Description |
|---|---|
| `doris-best-practices` | Apache Doris table design, sizing, and runtime query investigation (37 rules, 7 use-case templates, 4 sizing guides) |
| `doris-architecture-advisor` | Workload-aware architecture design (8 decision rules, 10 worked industry examples) |

## How to use

Install with the open [`skills`](https://github.com/vercel-labs/skills) CLI — it works
across agent tools (Claude Code, Cursor, Codex, Cline, Amp, …), auto-discovers both
skills in this repo, and bundles their `references/`:

```bash
npx skills add apache/doris-skills
```

Or copy them in manually:

```bash
cp -r skills/* ~/.claude/skills/
```

For the structured-diagnosis path (query profiles, tablet health), also install
doriscli. The recommended way is from **npm**, which ships prebuilt binaries (no
Rust toolchain, no compile step):

```bash
npm install -g @apache-doris/doriscli
doriscli --version
```

For other platforms, or to build from source, see the companion `doris-cli`
repository. Without doriscli, the skills use the SQL + HTTP fallback automatically.

## Authoring rules

- Write `doriscli` and `Apache Doris` directly. **Never** introduce a downstream
  distribution's brand strings — CLI names, console URLs, env-var prefixes, hostnames.
- Cloud-mode behavior (storage-compute separation, `replication_num=1`, file cache) is
  **Doris kernel architecture** — describe it neutrally as "cloud mode" / "storage-compute".
  Managed-service behavior (suspend/resume, automatic node-count management, billing) is
  out of scope; point at the user's cluster-management console rather than naming a product.
- If you rely on a new doriscli command or output field, add it to
  [CLI-CONTRACT.md](CLI-CONTRACT.md) so the two repositories stay in sync.

## Layout

```
doris-skills/
├── README.md
├── CLI-CONTRACT.md            # doriscli commands + JSON fields the skills depend on
└── skills/
    ├── doris-best-practices/
    └── doris-architecture-advisor/
```

## License

Apache-2.0
