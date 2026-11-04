# 4. Self-review the current code once, with a purpose

Set aside, for now, the reasoning you had while implementing, and check again from the current diff and the call relationships:

1. Does the change deliver the whole behavioral promise? Are any entry points, related paths, configs, or error handling missing?
2. Does the change alter a contract it was not authorized to alter? Are success, failure, boundary, and resource behavior consistent?
3. Can the tests catch the target defect? Do they bypass the real path, or prove only the internal shape of the code?
4. Do the description, comments, and examples match the final implementation? Were they updated when new scope turned up?
5. Does the change carry unrelated refactors, generated files, debug switches, temporary mutations, or sensitive information?

When the project defines a self-review checklist, also give a conclusion for each of its items; for example, the Doris `AGENTS.md` requires the self-review to cover the key checkpoints of the code-review skill.

Rule on each problem found against the source, an actual run, or an explicit contract. Fix the ones you accept and re-verify as needed; keep a short reason for each one you reject; write the ones you cannot settle as limitations. Don't call the self-review an independent review, and don't invent problems to fill the checklist.

Checkpoints that need wide evidence gathering (parallel paths, protocol definitions on each release branch, persistence and replay paths, and so on) can go to subagents, and the main session still rules on each conclusion; see `references/subagents.md`. After fixes, re-verify the affected conclusions by stage 5.
