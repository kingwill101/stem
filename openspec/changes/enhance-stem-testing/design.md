## Approach

- Implement chaos/performance tests using the in-memory broker/backend to keep dependencies light and deterministic.
- Use tagged tests (`@Tags(['soak'])`) for long-running scenarios so CI can opt-in or exclude.
- Write a coverage helper script invoking `dart test --coverage` and summarising results; integrate into a `run_quality_checks.sh` wrapper that can run format/analyze/test/coverage sequentially.
- Document quality gates in README and the process roadmap, linking to the new scripts.
