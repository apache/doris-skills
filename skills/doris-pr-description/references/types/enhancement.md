# Enhancement

Title tag: `improvement`. Use when an existing capability works as designed and the PR makes it better: usability, error messages, observability, limits, configurability, or compatibility with other systems. If the old behavior was a defect, use Bugfix; if users gain a new capability, use Feature.

## What reviewers check

- What exactly changes for users, and why is the change needed?
- Are existing users affected (their SQL, data, configs, and clients), especially after upgrading?
- Is a new config really needed, and is its default right?
- Why this particular edit? In Doris Enhancement PRs, the reason behind an individual edit is the piece of information reviewers most often have to ask for; give it in Notes for Reviewers.

## Background

How the capability works today, from the user's side first, and the part of it that this PR changes.

## Problem Summary

What is inconvenient or limited today, who runs into it, and what the PR changes, in one sentence. Then what an upgraded cluster does by default, since that is what existing users meet first.

## Details

- **Before and after** (required): the exact behavior before and after: the output, the error text, the limits, the defaults. Show a short example when words alone are ambiguous.
- **Configs and defaults** (required): new or changed configs and session variables, with their defaults and whether they can change at runtime; or `None`.
- **Impact on existing users** (required): what existing SQL, data, metadata, privileges, and clients will see, including after a running cluster is upgraded. When a default changes, give the value an upgraded cluster ends up with, and whether values persisted earlier (`SET GLOBAL`, `fe.conf`, table properties) override it.
- **Results** (when the change also improves performance): as in Performance.
- **Migration** (when something is deprecated or replaced): the steps for users, the compatibility window, and how to roll back.

## Testing

Regression tests for the new behavior, negative tests, and a test that the old behavior still works wherever compatibility is promised.

## Establish during development

What only development can establish, for the handoff file (`references/development.md`):

- The exact behavior before and after, from running the same input on the old and the new code: the output, the error text, the limits.
- For a changed default: the value an upgraded cluster ends up with, and whether values persisted earlier (`SET GLOBAL`, `fe.conf`, table properties) override it.
- A test that the old behavior still works wherever compatibility is promised.
- Why each non-obvious edit was made; Notes for Reviewers needs it.
