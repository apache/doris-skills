# Feature

Title tag: `feature`. Use when users get a capability they did not have: new SQL syntax, a function, a data source or catalog type, a privilege, a system table, or a switch that enables new behavior. Between Feature and Enhancement, choose Feature.

A Feature PR must link an issue that holds the use case and the proposed design. If there is none, Create and Update modes draft one with `references/issue.md`, describing the approach as built, and open it before the PR once the user confirms.

## What reviewers check

Feature PRs draw about two and a half times as many review comments as bug fixes, and design questions come up on three quarters of them:

- Should this be exposed at all, and in this shape: the syntax, the names, the defaults?
- Is the logic in the right layer?
- Were alternatives considered, and where does the design discussion stand?
- Does it work with mixed FE and BE versions during a rolling upgrade, and with existing metadata?

## Background

The concepts and the existing Doris feature this builds on, such as what row lineage is in the Iceberg v3 spec and how Doris reads v3 tables today. A Feature's reviewers often meet these concepts for the first time.

## Problem Summary

The use case (who needs this, and what they do today without it) and what the PR adds, in one sentence. Then, as `references/write.md` describes, what else the feature had to handle when the diff is larger than that sentence suggests, such as other settings that would defeat it, and what existing users see after an upgrade, which for a feature that is off by default is usually nothing.

## Details

- **Scope** (required): what is supported and what is explicitly not, and which modules change. Unsupported cases, and how they fail, matter as much as supported ones.
- **Design** (required): the approach, the alternatives considered and why they were rejected, and where the design was discussed (the issue, a dev@ thread, a design doc) and its status. If there was no discussion, say so; when the issue was opened together with this PR, say that, for example `Proposed in #59001, opened with this PR; not discussed yet`.
- **Usage** (required): a complete example that a reviewer can paste: the new SQL syntax, function calls, catalog properties, configs, or session variables, with the expected output where it helps.
- **Default behavior** (required): the default values, and whether the feature is on by default or how to turn it on.
- **Compatibility** (required): FE and BE of different versions during a rolling upgrade, old metadata and images, old configs, existing tables and data, and downgrade. A bare `None` is not enough here; say why nothing is affected.
- **Persistence and failure handling** (when the feature persists metadata or data): the EditLog and image, replay, master failover, BE crashes, retries, and what happens to half-finished work.
- **Security and privileges** (when the feature adds privileges or authentication, or connects to hosts that users name): the default and minimum privileges, and audit logging. A new outbound request to a user-named host is an SSRF surface, and `AGENTS.md` requires the PR description to call it out together with the privilege needed to reach it.
- **Deployment modes** (when behavior differs between cloud and shared-nothing modes): describe each mode.
- **Follow-up plan** (when the feature lands in phases): what comes next, and where it is tracked.

## Testing

Positive cases, negative cases, boundaries, NULLs, concurrency, error inputs, and privileges, whichever apply, with the suites that cover them. A feature without negative tests usually draws a review comment.

## Establish during development

What only development can establish, for the handoff file (`references/development.md`):

- The user-visible contract chosen (syntax, names, defaults, configs, privileges) and the alternatives rejected, with the reasons. The issue and the Design field are written from them.
- The parts the feature grew into beyond its first idea, such as other settings that must be locked for it to hold, and why each is needed. Problem Summary and the Change map are written from them.
- What is not supported, and a test of how it fails.
- The compatibility facts: whether FE and BE of different versions work together during a rolling upgrade, what is persisted in the EditLog and image, any Thrift or Protobuf change (`gensrc/AGENTS.md`), and downgrade.
- Negative tests, and privilege tests that connect as a user other than `root`.
- That a PR pipeline runs the new suites (`references/facts/existing-tests.md`).
