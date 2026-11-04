# Existing tests of the changed code

Every PR that changes code needs these facts: a test that asserts the changed behavior and that the diff leaves unchanged is a stop condition, Bugfix uses them for Why existing tests missed it, Test PRs for What existing tests miss, and every type for Testing. Development records them in the handoff file; the PR step collects them here only when there is no handoff file or it lacks them.

Look at both layers: the unit tests (`fe/*/src/test/`, `be/test/`, `cloud/test/`) and the end-to-end regression suites under `regression-test/suites/`. Search the code as it was before the change, at `$base`, the merge base with `upstream/master`. Search for the classes and functions the change touches, and for what a user would type or see: the SQL statement, function, config, or error text.

```bash
git grep -l -e '<class or function>' "$base" -- 'fe/*/src/test/*' be/test cloud/test
git grep -l -i -e '<SQL statement, config, or error text>' "$base" -- regression-test/suites
```

Read the closest cases, not only their names: what they set up (data, configs, the user they connect as), what they assert, and whether they mock the faulty code. Regression cases run as `root` unless they `connect` as a user they create, so they pass every privilege check. Then check that CI runs them: a suite's groups are in its `suite("<name>", "<groups>")` line, and each pipeline's config in `regression-test/pipeline/<pipeline>/conf/` (`regression-conf.groovy`, or `regression-conf-custom.groovy` for the cloud and vault pipelines) lists the groups, suites, and directories it skips; P0, for example, skips the `p1` and `p2` groups. The pipeline's `run.sh` can skip more: `cloud_p0` passes `-runNonConcurrent false`, so it never runs `nonConcurrent` suites. A suite's `docker(...)` block returns without running, and the suite still passes, unless the config sets `excludeDockerTest = false`; the default is `true`. Coverage can also be partial the other way: pipelines with `use_fuzzy_session_variable=true` randomize session variables in `SessionVariable.initFuzzyModeVariables()`, such as `enable_spill`, so an existing suite may reach a path in only some runs. The same checks tell whether a PR pipeline runs a new test.

A test that asserts the old behavior, in an assertion or in its `.out` file, fails once the change lands, so check whether the diff updates it.
