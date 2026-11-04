# Refactor: verify that observable behavior is preserved

First establish which behavior must be preserved, then restructure the internals. Prefer reusing behavior tests, and don't write mirror tests around new class names, the way functions are split, or private fields.

In differential verification, the baseline and the candidate must use the same inputs and conditions. Besides the successful results, check contracts such as errors, ordering, side effects, and resource release as the risk calls for. If behavior changes too, verify that part by the bugfix or new-feature strategy, and don't call it just a refactor.

When moving a lot of code, put pure moves and renames in commits apart from logic changes, so that reviewers can skip the pure moves. When the change is on a hot path, measure whether performance changes. Note whether anything persisted or sent between processes changes; that decides whether a plain revert is possible if something goes wrong.
