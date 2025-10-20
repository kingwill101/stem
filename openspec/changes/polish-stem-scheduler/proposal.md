## Summary
- Tighten Beat (scheduler) behavior with explicit CLI management commands, stronger locking, and jitter tooling.
- Improve operator feedback: show next fire time, last run status, and allow dry-run evaluation of schedules.

## Motivation
- Current scheduler API is code-driven with minimal visibility; operators cannot audit or adjust entries without editing config files.
- Distributed deployments need clearer locking semantics to avoid double fire.

## Goals
- Provide CLI for `stem schedule list/show/apply/delete/dry-run` backed by Redis schedule store.
- Enhance locking to include per-entry lease extensions and publish diagnostics when contention happens.
- Persist execution metadata (`nextRunAt`, `lastError`, jitter value) accessible to CLI and observability pipeline.

## Non-Goals
- Implementing advanced calendar expressions beyond cron/interval.
- Adding a UI dashboard (CLI focused).

## Risks & Mitigations
- **Lock contention**: Use predictable Redis keys with TTL and include jitter to avoid thundering herd.
- **CLI drift**: Reuse existing schedule store operations to avoid duplicate logic.
- **Backward compatibility**: Provide migration notes for existing config files (e.g., new fields).

## Open Questions
- Should CLI support interactive editing? (Out of scope for first pass; focus on declarative apply via YAML/JSON.)
- How to handle very long jitter? (Cap at configured maximum to maintain schedule fairness.)
