# Configs, dependencies, builds, and data migrations

Choose the checks by the actual subtype, rather than stacking up every requirement:

- **Configs:** parsing, defaults, missing or invalid values, and the startup or execution paths actually affected.
- **Dependencies:** the resolved versions, the lockfiles, the affected interfaces, and the builds and tests; cover the platforms that must be supported as the task and the project's rules require.
- **Builds:** the actual build outputs and the related configs. Confirm that the build output comes from the candidate code, and don't let a stale cache pass for a new build.
- **Migrations:** on isolated, disposable data, verify the counts, key values, and constraints after the conversion, and the error handling. Verify idempotency, compatibility, rollback, or resumption only where the product promises them; state irreversible operations plainly, and don't invent a rollback promise.

Don't change production data to fill gaps in local evidence. When the environment falls short, record the unverified paths and a follow-up check that someone can reproduce.
