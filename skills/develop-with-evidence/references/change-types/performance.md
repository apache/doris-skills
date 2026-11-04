# Performance: verify the conditions under which the gain holds

- Before optimizing, locate the bottleneck: confirm it with a profile, a flame graph, counters, or a cost that follows directly from the code, and keep the evidence.
- Check correctness first, then measure performance; where needed, check the execution plan or the target path that was actually chosen.
- Fix the versions, build options, resources, inputs, configs, and cache conditions of the baseline and the candidate. State what the timing actually covers and how the system was warmed up.
- Choose at least the target workload and one kind of workload that, judging by the mechanism, may not benefit or may get slower. Widen only the dimensions that could change the conclusion.
- Record the number of samples, the statistic used, and the noise; don't pick only the best run. When the result can't be told apart from the noise, write "improvement not shown".
- Disclose the regressions and the memory or complexity costs you observed. When the gain doesn't cover what the requirement needs, narrow the conditions under which the optimization applies, change the implementation, or raise the trade-off as an open question.
- Prefer protecting the optimization through structure, counts, or resource behavior. Use an elapsed-time threshold as a key regression assertion only when time itself is the contract and the environment is controlled.
