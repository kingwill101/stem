## 1. Research & Design
- [x] 1.1 Audit existing broker/backend DLQ pathways (in-memory + Redis) and document replay affordances.
- [x] 1.2 Draft CLI UX & safety rules in `design.md`, review with team.

## 2. Implementation
- [x] 2.1 Implement broker/backend APIs needed for listing and replaying DLQ entries (Redis + in-memory).
- [x] 2.2 Add `stem dlq list/show` commands with pagination, sampling, and metadata display.
- [x] 2.3 Add `stem dlq replay/purge` commands with confirmation prompts, limit flags, and optional delay.
- [x] 2.4 Wire CLI commands through middleware/events so replayed tasks are observable.

## 3. Validation
- [x] 3.1 Unit tests for CLI argument parsing and safety guards.
- [x] 3.2 Integration tests covering replay to success/failure paths using Redis fixtures.
- [x] 3.3 Update documentation (operator handbook) with DLQ workflows.
