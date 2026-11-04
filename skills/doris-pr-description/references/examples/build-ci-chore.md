# Build/CI/Chore: example

Illustrative: the details are made up.

````markdown
Title: [chore](build) Fail fast in build.sh when third-party libraries are missing

### Background

The BE links against dozens of third-party libraries, installed under `thirdparty/installed`. Contributors get them by running `thirdparty/build-thirdparty.sh`, which takes hours, or by downloading a prebuilt package. `build.sh` assumes they are present and starts the CMake build right away.

### What problem does this PR solve?

Issue Number: None
Related PR: None
PR Type: Build/CI/Chore

Problem Summary:

When `thirdparty/installed` is missing or incomplete, `./build.sh --be` fails after about ten minutes with an unrelated CMake error, and new contributors regularly ask about it. This PR checks for the required libraries up front and prints how to get them.

### Details

- **Affected:** `build.sh` on Linux and macOS, x86_64 and ARM64. CI images already contain the libraries, so CI jobs are unaffected.
- **Developer and release impact:** A build with missing third-party libraries now stops within a second, with a message pointing to `thirdparty/build-thirdparty.sh` and the prebuilt packages. Release builds don't change.
- **License and third-party:** None.
- **Rollback:** Revert this PR; nothing else depends on the check.

### Testing

- `./build.sh --be` with `thirdparty/installed` removed stops at once with the new message, on Linux x86_64 and macOS ARM64.
- `./build.sh --be --fe` with a complete `thirdparty/installed` builds as before.

### Release note

None

### Check List (For Author)

- Behavior changed: No
- Does this need documentation: No
- Pre-submission status: Ready

### AI Disclosure

- Tool: Claude Code (Claude Opus 5.5)
- Generated: the check in `build.sh` and this description
- Human review: The author reviewed the script change and ran both builds.
````
