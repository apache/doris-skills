# Build/CI/Chore

Title tag: `chore`. Use for build scripts, CI workflows, developer tooling, code style, repository maintenance, Doris version bumps, and documentation inside this repository (`README`, code comments, `AGENTS.md`, skills). User documentation lives in `apache/doris-website`. Third-party upgrades are Release/Dependency.

## What reviewers check

- What problem does this solve, and is there evidence that it does? Reviewers question this on about a quarter of these PRs.
- Which platforms, toolchains, and pipelines does it affect?
- Does it carry unrelated changes?

## Background

What the build step, CI job, or tool does today, and who relies on it.

## Problem Summary

The problem (a failing job, a slow build, a missing check), with a link if there is one, and the change in one sentence.

## Details

- **Affected** (required): the platforms (Linux, macOS, x86_64, ARM64), toolchains (JDK, compilers, Python), workflows and CI jobs, Docker images, and third-party build scripts that this touches.
- **Developer and release impact** (required): what changes for developers (new steps, new failures, slower or faster builds) and for the release process; or `None`.
- **License and third-party** (required): whether lockfiles, third-party artifacts, `LICENSE`, `NOTICE`, or `dist/LICENSE-dist.txt` need updates; or `None`.
- **Rollback** (required): how to restore the previous state if this breaks builds or CI, usually a revert, and whether anything else must be undone, such as caches, runner images, or secrets.
- **CI permissions and secrets** (when workflow permissions, tokens, or secrets change): the security boundary, and why the permissions are the minimum needed.

## Testing

The commands and CI jobs that actually ran, on which platforms, and their results. For a fix to a failing job, show it failing before and passing after.

## Establish during development

What only development can establish, for the handoff file (`references/development.md`):

- The commands and CI jobs run, on which platforms, and their results; for a fix to a failing job, the run that fails before it and the run that passes after.
