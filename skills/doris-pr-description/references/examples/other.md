# Other: example

Illustrative: the PR numbers and details are made up.

````markdown
Title: [other](ci) Run the full pipeline on unmodified master to check the TeamCity cache

### Background

PR pipelines run on TeamCity, which reuses cached build outputs between runs to save time.

### What problem does this PR solve?

Issue Number: None
Related PR: #59201 (one of the PRs with the unexplained P0 failures)
PR Type: Other

Problem Summary:

For several days, P0 has failed on unrelated PRs with missing-class errors. This draft runs the full pipeline on unmodified master to check whether the TeamCity build cache is the cause. It is not meant to be merged.

### Details

- **Why Other:** It is an experiment, not a change, and will be closed when the pipeline finishes.

### Testing

- Not applicable; the pipeline run is the experiment.

### Release note

None

### Check List (For Author)

- Behavior changed: No
- Does this need documentation: No
- Pre-submission status: Not ready: an experiment that will be closed, not merged

### AI Disclosure

- Tool: Claude Code (Claude Opus 5.5)
- Generated: this description
- Human review: The author checked the description.
````
