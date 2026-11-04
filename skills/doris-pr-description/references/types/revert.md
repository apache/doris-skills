# Revert

Title: GitHub's default `Revert "<original title>"`. If the original title has no `[type](scope)` prefix, use `[revert](<scope>) Revert "<original title>"` so the title check passes. Use when the PR reverts one or more earlier PRs, fully or partly.

A revert is usually urgent: CI is red, or a release is blocked. Keep the description short, with one or two sentences per field.

## What reviewers check

- Does the original author know, and is a forward fix already on the way?
- Is a revert really necessary, or can the problem be fixed forward?
- Is the revert complete, and does anything merged later depend on the reverted code?
- Is there a test showing the revert fixes the problem?

## Background

What the reverted PR changed and why it was made, in one or two sentences.

## Header and Problem Summary

`Related PR` must name the reverted PR. The summary states what breaks and the evidence: the failing test or CI job, the error, the impact on users, or the compatibility problem.

## Details

- **Why not fix forward** (required): why reverting is better than fixing now: the root cause is unknown, the fix needs a redesign, a release is blocked.
- **Original author notified** (required): who was told, and where, for example `Yes, @<login> agreed in #N`. Mentioning the author in this PR counts.
- **Follow-up** (required): how the change comes back, for example the author re-lands it with a fix, tracked in an issue; or that it is not coming back, and why.
- **Completeness** (when later commits touched the reverted code, or the revert is partial): what was kept and why, and the commits that depend on the reverted code.
- **Workaround** (when users of a released version are affected): what they can do until a fix ships.

## Testing

The CI pipelines that must pass, or the failing test that passes again after the revert. Extra smoke tests are optional.

## Establish during development

What only development can establish, for the handoff file (`references/development.md`):

- That the problem is gone with the revert, for example the failing test passing again.
- Which commits merged after the reverted PR touch the same code, and whether they depend on it.
