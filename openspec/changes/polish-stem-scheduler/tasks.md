## 1. Design
- [ ] 1.1 Document enhanced locking model, jitter calculation, and CLI UX in `design.md`.
- [ ] 1.2 Map data model changes for schedule metadata (next run, last error, jitter).

## 2. Implementation
- [ ] 2.1 Update Redis schedule store to persist `nextRunAt`, `lastRunAt`, `lastError`, and jitter metadata per entry.
- [ ] 2.2 Strengthen distributed lock by adding lease renewals and contention visibility metrics.
- [ ] 2.3 Implement `stem schedule` CLI subcommands (list/show/apply/delete/dry-run) with YAML/JSON support.
- [ ] 2.4 Add validation for schedule definitions (cron parsing, interval bounds, jitter caps).

## 3. Validation
- [ ] 3.1 Integration tests for multi-beat deployments verifying single execution with new lock semantics.
- [ ] 3.2 CLI tests covering CRUD workflows and dry-run output.
- [ ] 3.3 Documentation updates for scheduler operations playbook.
