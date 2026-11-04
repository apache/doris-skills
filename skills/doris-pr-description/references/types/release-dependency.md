# Release/Dependency

Title tag: `deps`. Use when the PR upgrades, downgrades, adds, or pins a third-party dependency: libraries in `thirdparty/`, Maven dependencies, Python packages, Docker base images. Doris version bumps and other release chores are Build/CI/Chore.

## What reviewers check

- Is this version already superseded? Check before writing.
- Does the license change, and do `LICENSE`, `NOTICE`, or `dist/LICENSE-dist.txt` need updates?
- Which CVEs or upstream fixes motivate the upgrade, and what else changed upstream that could affect Doris?
- Does it still build and run everywhere Doris does?

## Background

What the dependency is, what Doris uses it for, and where it is built or bundled: `thirdparty/`, a Maven module, a Python package.

## Problem Summary

Why upgrade now (a CVE, an upstream fix Doris needs, compatibility, a feature, or the old version reaching end of life), in one or two sentences.

## Details

- **Versions** (required): the dependency, old version → new version, where it comes from, and the checksum or pinned commit if the build pins one.
- **Upstream changes** (required): the upstream changes that matter to Doris (fixes, CVEs by ID, behavior or ABI changes, license changes), with a link to the upstream release notes. Don't paste the whole changelog.
- **Compatibility** (required): the platforms and toolchains checked (JDK, glibc, OS, CPU architecture, Python, compiler), and any effect on data that Doris reads or writes through this library.
- **Rollback** (required): how to return to the old version and who would be affected, for example whether data written with the new version can still be read after rolling back.

## Testing

The full build, unit tests, regression tests, and packaging, with their results; whether prebuilt third-party packages and caches were rebuilt and checksums updated; any effect on reproducible builds.

## Establish during development

What only development can establish, for the handoff file (`references/development.md`):

- The platforms and toolchains built and tested, and the results.
- Whether checksums, prebuilt third-party packages, and caches were updated.
