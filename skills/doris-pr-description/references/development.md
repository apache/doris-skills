# What development must establish

A development skill such as `develop-with-evidence` reads this file at the start of development, and then only the files it points to. Some facts this standard asks for exist only while the code is being written: a test that fails before the fix, benchmark numbers, the alternatives to a design, the reason for an edit. And when there is a handoff file, the PR step takes the facts in it as given and doesn't collect them again (`references/handoff-intake.md`), so development records every fact the description needs, apart from the few that only the PR step can know.

1. Classify the change by `references/classify.md` and read its type file in `references/types/`. The required fields and "What reviewers check" are part of what development verifies, and the "Establish during development" list says what to record.
2. When the change grows past its first idea, such as a switch that needs other settings locked or a fix that needs a refactor, note each part it adds and the problem that part handles. Problem Summary and the Change map are written from them.
3. Collect the facts that need looking up, by the file for each:
   - for every change to code, the existing tests of the changed code, the tests that assert the changed behavior, and whether a PR pipeline runs the new tests: `references/facts/existing-tests.md`;
   - for a Bugfix, the PR that introduced the bug and the release branches that have it: `references/facts/bugfix-origin.md`;
   - when the change moves a submodule pointer, the range it moves and whether the new pin is on the branch: `references/facts/submodules.md`.
4. Record the results in English in the handoff file:
   - in its description draft: the PR type, the title, Background, the problem and the approach for Problem Summary, `Issue Number`, `Related PR`, the type's fields, Testing, Release note, and the Check List with the documentation plan. `Related PR` holds the PRs known from the work, such as the one that introduced a bug or the ones the change builds on or depends on, or `None`; don't search GitHub for other PRs on the same problem;
   - beside the draft: the decisions and their alternatives, the parts of the change, the reasons for non-obvious edits, the existing tests, the evidence, the pre-submission status, and how AI was used.

Left to the PR step: the line counts of the final diff, the review threads of an open PR, the author's statement on how much of the AI-generated work they reviewed, the issue a Feature without one needs, and the final wording of the description.

In this flow a Feature needs no agreed design before development: the developer chooses the approach, and Create mode drafts and opens the issue that describes it.
