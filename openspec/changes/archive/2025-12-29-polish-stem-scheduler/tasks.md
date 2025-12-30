## 1. Design
- [x] 1.1 Document enhanced locking model, jitter calculation, and CLI UX in `design.md`.
- [x] 1.2 Map data model changes for schedule metadata (next run, last error, jitter).

## 2. Implementation
- [x] 2.1 Update Redis schedule store to persist `nextRunAt`, `lastRunAt`, `lastError`, and jitter metadata per entry.
- [x] 2.2 Strengthen distributed lock by adding lease renewals and contention visibility metrics.
- [x] 2.3 Implement `stem schedule` CLI subcommands (list/show/apply/delete/dry-run) with YAML/JSON support.
- [x] 2.4 Add validation for schedule definitions (cron parsing, interval bounds, jitter caps).

## 3. Validation
- [x] 3.1 Integration tests for multi-beat deployments verifying single execution with new lock semantics.
- [x] 3.2 CLI tests covering CRUD workflows and dry-run output.
- [x] 3.3 Documentation updates for scheduler operations playbook.
