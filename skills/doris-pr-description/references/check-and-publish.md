# Steps 5 and 6: Check, show, and publish

## 5. Check the draft

```bash
python3 <this-skill-dir>/scripts/check_pr.py <draft-file> --diff "$base..<head>"
```

`--diff` gives the checker the size of the change, so that it can tell whether the diff needs a Change map; with `--pr` it takes the size from GitHub. The checker verifies the title format, the declared type, the sections (Background first), the type's required fields, the Change map of a large diff, the Check List lines, the Feature issue rule, leftover placeholders and guidance comments, and length. It ignores HTML comments when it judges whether a section is empty, since GitHub doesn't show them. Fix every error and run it again; treat warnings as prompts to reconsider. A draft with `TODO(author)` is reported as not ready, which is expected in Rewrite mode and for the issue TODO of step 4. The checker can't judge content, so before showing the draft, re-read it against the type's "What reviewers check" list.

## 6. Show, then publish

Show the title and description, and the issue draft for a Feature without an issue, followed by a short list of what the user should know: the remaining TODOs, with the `confirm` TODOs and the problems that no field asks about listed apart; statements you inferred but could not verify; evidence or other facts in the handoff file that have gone stale, production files that none of its parts accounts for, and the facts collected because it lacked them; facts from the original description that you changed or dropped; later changes that the description leaves out; and, when there is a `Prompts` line, that it summarizes the user's own messages and will be public. In Create and Update modes, ask in the same message for confirmation and for what the AI Disclosure needs from the user: how much of any AI-generated code they reviewed, and, if the code was written outside this conversation and the handoff file records no direction, whether they want to describe their prompts. When the pre-submission status is `Not ready`, say so, and open the PR as a Draft if the user still wants it opened. Rewrite mode ends with this report.

Publish only after the user confirms, or when their request already said to publish without review:

```bash
# Feature without an issue: create the issue first; then replace the Issue Number TODO in the
# draft with close #<N>, add the number wherever the description names the issue, and run the
# checker again
tail -n +3 <issue-file> > <issue-body-file>  # the issue body without the Title line
gh issue create --repo apache/doris --title "<issue title>" --body-file <issue-body-file>

tail -n +3 <draft-file> > <body-file>        # the description without the Title line

# Create: push to the user's fork, then open the PR against apache/doris
# (add --draft for Other, or when the pre-submission status is Not ready)
git push -u <fork-remote> HEAD
gh pr create --repo apache/doris --base master --head <fork-owner>:<branch> \
  --title "<title>" --body-file <body-file>

# Update: only the user's own PR, or one they explicitly ask you to edit
gh pr edit <N> --repo apache/doris --title "<title>" --body-file <body-file>
```

## Check mode

Run `python3 <this-skill-dir>/scripts/check_pr.py --pr <N>`, read the description against the type's "What reviewers check" list, and report both results. Check mode changes nothing on GitHub.
