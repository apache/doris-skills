# Qualified reviewer runtime

Establish the reviewer runtime before reading source. A pipeline-equivalent review accepts only:

| Host | Models | Effort |
|---|---|---|
| Codex | `gpt-6-astra`, `gpt-6.2-astra`, `gpt-6.2-sol`, `gpt-6.1-sol`, `gpt-6-sol` | `xhigh`, `max`, or `ultra` |
| Claude Code | `claude-fable-5-1`, `claude-fable-5-1[1m]`, `claude-opus-5-5`, `claude-opus-5-5[1m]`, `claude-fable-5`, or `claude-fable-5[1m]` | `xhigh` or `max` |
| Antigravity | `gemini-4-carbon`, `gemini-4-neon` | `high` (`gemini-4-carbon` only) or `xhigh` (`gemini-4-neon` only) |

Prefer `gpt-6-astra` on Codex (default effort `xhigh`), Fable 5.1 on Claude Code (default effort
`xhigh`), and `gemini-4-carbon` (`high`) on Antigravity. Use another allowlisted model only when
explicitly requested by the user or when the preferred model is unavailable.

`gpt-5.6-sol`, `claude-opus-5`, and `claude-opus-5[1m]` are no longer eligible.
The same policy applies to the lead and every substantive coverage reviewer.

`ultra` is accepted only when the Codex host explicitly exposes and actually uses that setting.
The GPT-6.2, GPT-6.1 Sol, and GPT-6 Sol APIs support effort only through `max`; do not relabel an
API `max` run as `ultra`.

On Antigravity, CLI and `swarm` identifiers append the effort suffix (`gemini-4-carbon-high`,
`gemini-4-neon-xhigh`), and the UI labels `xhigh` on Neon as `Extra`. Always split them into the
canonical receipt fields (`--model gemini-4-carbon --effort high` or
`--model gemini-4-neon --effort xhigh`): `gemini-4-carbon` publishes no `xhigh` tier, and
`gemini-4-neon` at `high` or lower is ineligible. Never treat an `Orchestrator` session
(`gemini-pro-orchestrator*`) as qualified, because Orchestrator hands execution steps to
`gemini-4-hydrogen`.

Validate the exact values with:

```bash
$S/review-runtime-policy.sh check "<model>" "<effort>"
```

Keep the actual reviewer's exact model and effort for `record-review-runtime.sh` after the PR
context is prepared, including when a fallback or delegated reviewer is used. Never substitute
the parent task's model or a fixed default in the receipt.

Never infer task settings from a global config file. Continue in the current task only when its
model and effort are exposed explicitly, pass the policy check, and satisfy the preference above.

## Codex delegation

When the current task cannot be retained under the rules above, spawn one lead reviewer with:

- `fork_turns: "none"`
- `model: "gpt-6-astra"`
- `reasoning_effort: "xhigh"`

If Astra is unavailable, fall back to `gpt-6.1-sol` with `xhigh`. If the user explicitly requests
another qualified runtime, use its exact model and supported effort instead. Preserve a current
preferred runtime's qualified effort rather than resetting it to `xhigh`.

Pass the original request, current working directory, and absolute path to this skill. Tell the
lead to execute the whole skill. Wait for it and relay its result; do not read source or repeat the
review in the parent. A full-history fork cannot apply model or effort overrides.

## Antigravity delegation

`invoke_subagent` exposes only coarse tiers (`inherit`, `flash`, `pro`) and cannot upgrade an
unqualified parent to `gemini-4-carbon-high` or `gemini-4-neon-xhigh`. Retain the current task
(and spawn coverage reviewers via `invoke_subagent` with `TypeName: "self"`, `Model: "inherit"`)
only when the host explicitly confirms standalone `Gemini 4 Carbon (High)` or (when requested or
when Carbon is unavailable) `Gemini 4 Neon (Extra)` / `gemini-4-neon-xhigh`.

Otherwise, delegate the lead and substantive coverage reviewers with `swarm` (`action: "add"`)
pinned to `model: "gemini-4-carbon-high"`, falling back to `model: "gemini-4-neon-xhigh"` if
Carbon is unavailable, or to the user's explicitly requested allowlisted runtime. Record the
actual delegated reviewer's canonical model and effort in `record-review-runtime.sh`.

## Coverage reviewers

Use the same qualified model and effort for every substantive coverage reviewer. On Codex, use
`fork_turns: "none"` with explicit overrides and include all required paths, SHAs, focus points,
prompt text, and ledger destinations in each message. On Antigravity, either inherit from an
explicitly confirmed standalone qualified parent (`TypeName: "self"`, `Model: "inherit"`) or pin
each worker via `swarm` to the exact qualified model-effort variant.

Runtime identity is an auditable local attestation, not a cryptographic proof. If the host cannot
guarantee these settings, complete the local documents but do not post a pipeline-equivalent PASS.
