# Qualified reviewer runtime

Establish the reviewer runtime before reading source. A pipeline-equivalent review accepts only:

| Host | Models | Effort |
|---|---|---|
| Codex | `gpt-6-astra`, `gpt-6-sol` | `xhigh`, `max`, or `ultra` |
| Claude Code | `claude-fable-5-1`, `claude-fable-5-1[1m]`, `claude-opus-5-5`, `claude-opus-5-5[1m]`, `claude-fable-5`, or `claude-fable-5[1m]` | `xhigh` or `max` |

Prefer `gpt-6-astra` on Codex and Fable 5.1 on Claude Code, with `xhigh` as the default
qualified effort. Use another allowlisted model only when explicitly requested by the user or
when the preferred model is unavailable.

`gpt-5.6-sol`, `claude-opus-5`, and `claude-opus-5[1m]` are no longer eligible.
The same policy applies to the lead and every substantive coverage reviewer.

`ultra` is accepted only when the Codex host explicitly exposes and actually uses that setting.
The GPT-6 Sol API supports effort only through `max`; do not relabel an API `max` run as `ultra`.

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

If Astra is unavailable, fall back to `gpt-6-sol` with `xhigh`. If the user explicitly requests
another qualified runtime, use its exact model and supported effort instead. Preserve a current
preferred runtime's qualified effort rather than resetting it to `xhigh`.

Pass the original request, current working directory, and absolute path to this skill. Tell the
lead to execute the whole skill. Wait for it and relay its result; do not read source or repeat the
review in the parent. A full-history fork cannot apply model or effort overrides.

## Coverage reviewers

Use the same qualified model and effort for every substantive coverage reviewer. On Codex, use
`fork_turns: "none"` with explicit overrides and include all required paths, SHAs, focus points,
prompt text, and ledger destinations in each message.

Runtime identity is an auditable local attestation, not a cryptographic proof. If the host cannot
guarantee these settings, complete the local documents but do not post a pipeline-equivalent PASS.
