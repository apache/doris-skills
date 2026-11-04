# Drafting an issue

A Feature PR needs an issue that holds the use case and the proposed design. Other types may use an issue for long material, such as a reproduction script or design notes, that the PR then points to.

The developer chooses a Feature's approach while implementing it, so its issue is usually drafted at PR time, from the handoff file and the code: it describes the approach as built and the alternatives considered, and it is opened before the PR. Design discussion can continue in it. The handoff file supplies most sections: the goal and its acceptance results give Expected behavior and Acceptance criteria, the change's boundary gives Scope and non-goals, the decisions give Proposed design, and the compatibility evidence gives Risks and compatibility.

Draft the issue in a file in the format of a PR draft: line 1 `Title: <title>`, a blank line, then the body. Show it to the user, and create it only after they approve the text. Creating an issue notifies watchers of the repository.

```bash
tail -n +3 <issue-file> > <issue-body-file>  # the body without the Title line
gh issue create --repo apache/doris --title "<title>" --body-file <issue-body-file>
```

## Title

`[<Kind>][<Module>] <Description>`, where Kind is `Feature`, `Bug`, or `Enhancement`, the prefixes used by the repository's issue templates. For example: `[Bug][Iceberg] Scan returns NULL partition values after partition spec evolution`.

## Body

A Feature issue needs every section below; for other kinds, keep the sections that have content.

```markdown
### Background

Why this issue exists: the user scenario, the need, or the incident.

### Current behavior

What happens today. For a bug, include the Doris version and the deployment mode.

### Expected behavior

What should happen instead.

### Proposed design

The approach, the alternatives considered, and why they were rejected. For a Feature drafted at PR time, the approach as implemented.

### Impact

Who is affected: users, versions, deployment modes (cloud or shared-nothing), modules, and how severely.

### Reproduction or evidence

SQL, configs, logs, profiles, screenshots, links, or code paths.

### Scope and non-goals

What this issue covers, and what it deliberately does not.

### Acceptance criteria

The observable results or tests that mean the issue is done.

### Risks and compatibility

Upgrades, mixed FE and BE versions, metadata, storage formats, configs, privileges.

### Related

Related issues, PRs, design documents, dev@ threads, and upstream links.
```

A long design can live in a design document linked from Related, with a summary in Proposed design.

The same rules apply as for PR descriptions: write in English, state only facts you can trace, and leave out internal tracker IDs, private links, and customer names.
