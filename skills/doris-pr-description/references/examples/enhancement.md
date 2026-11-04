# Enhancement: example

Illustrative: the PR and issue numbers, names, and results are made up.

````markdown
Title: [improvement](load) Return the first filtered rows in the Stream Load response

### Background

Stream Load loads a file into Doris over HTTP. Rows that fail conversion or validation are filtered out, and the load still succeeds as long as their share stays below `max_filter_ratio`. The JSON response reports how many rows were filtered, and the BE writes the filtered rows to an error log that the response's `ErrorURL` points to.

### What problem does this PR solve?

Issue Number: close #58877
Related PR: None
PR Type: Enhancement

Problem Summary:

When Stream Load filters rows, its response only points to an `ErrorURL`. Users behind a proxy or in another network often cannot open that URL, so they cannot see why rows were rejected. This PR puts the first few filtered rows, with the reason for each, into the response itself. After an upgrade every response with filtered rows has the new field, and a BE config turns it off.

### Details

- **Before and after:** Before, the response reports `NumberFilteredRows` and an `ErrorURL`. After, it also has `FirstFilteredRows`: up to 5 entries, each with the row text (truncated to 512 bytes) and the reason, such as `{"row": "1,abc,2026-13-01", "reason": "column k3: invalid date value"}`. `ErrorURL` is unchanged.
- **Configs and defaults:** New BE config `stream_load_response_error_rows`: default 5, `0` turns the field off, and it can be changed at runtime.
- **Impact on existing users:** The response JSON gains one field. Clients that parse it leniently are unaffected; clients that reject unknown fields need the config set to `0`. Row text can contain user data, so it is truncated the same way as the `ErrorURL` content.

### Testing

- New regression test `load_p0/stream_load/test_stream_load_filtered_rows_response.groovy`: CSV and JSON loads with filtered rows, the config at 0, 1, and 5, and a row longer than 512 bytes.
- Existing Stream Load suites pass unchanged.

### Notes for Reviewers

- The reasons reuse the messages already written to the error log, so the response and `ErrorURL` always show the same text.

### Release note

Stream Load responses now include up to 5 filtered rows and the reason each was rejected, in the new `FirstFilteredRows` field. Set the BE config `stream_load_response_error_rows` to `0` to leave the field out.

### Check List (For Author)

- Behavior changed: Yes (see Details)
- Does this need documentation: Yes (apache/doris-website#2390)
- Pre-submission status: Ready

### AI Disclosure

- Tool: Claude Code (Claude Opus 5.5)
- Generated: this description
- Human review: The author wrote the code and edited this description.
````
