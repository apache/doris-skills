# Qualified reviewer runtime

Establish the reviewer runtime before reading source. A pipeline-equivalent review accepts only:

| Host | Models | Effort |
|---|---|---|
| Codex | `gpt-5.6-sol` | `xhigh`, `max`, or `ultra` |
| Claude Code | `claude-opus-5`, `claude-opus-5[1m]`, `claude-fable-5`, or `claude-fable-5[1m]` | `xhigh`, `max`, or `ultra` |

Validate the exact values with:

```bash
$S/review-runtime-policy.sh check "<model>" "<effort>"
```

Never infer task settings from a global config file. Continue in the current task only when its
model and effort are exposed explicitly and pass the policy check.

## Codex delegation

When either value is unavailable or ineligible, spawn one lead reviewer with exactly:

- `fork_turns: "none"`
- `model: "gpt-5.6-sol"`
- `reasoning_effort: "xhigh"`

Pass the original request, current working directory, and absolute path to this skill. Tell the
lead to execute the whole skill. Wait for it and relay its result; do not read source or repeat the
review in the parent. A full-history fork cannot apply model or effort overrides.

## Coverage reviewers

Use the same qualified model and effort for every substantive coverage reviewer. On Codex, use
`fork_turns: "none"` with explicit overrides and include all required paths, SHAs, focus points,
prompt text, and ledger destinations in each message.

Runtime identity is an auditable local attestation, not a cryptographic proof. If the host cannot
guarantee these settings, complete the local documents but do not post a pipeline-equivalent PASS.
