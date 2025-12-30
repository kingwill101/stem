## Implementation Tasks

- [x] Finalise the backend-agnostic interfaces (`WorkflowStore`, `EventBus`, `RunState`) and wire them into the core `stem` package alongside the developer-facing `Workflow` / `Flow` APIs.
- [x] Implement Redis-backed store/bus with Lua scripts for checkpoint idempotency, timer ZSETs, and topic fan-out; include configuration and disposal hooks.
- [x] Implement Postgres-backed store/bus using transactional tables (`wf_runs`, `wf_steps`), indexes, and `LISTEN/NOTIFY` integration for event fan-out.
- [x] Implement SQLite-backed store/bus leveraging WAL mode and lightweight polling for timers/topics; document limitations and tuning knobs.
- [x] Add the internal `workflow.run` task handler that executes/resumes flows, manages suspension semantics, and integrates with Stem’s lease/heartbeat/logging systems.
- [x] Build a `stem wf` CLI group (`start`, `ls`, `show`, `cancel`, `rewind`, `emit`) plus automated tests.
- [x] Create comprehensive contract tests shared across backends plus end-to-end workflow scenarios (sleep, awaitEvent, failure/retry, cancellation).
- [x] Document setup and usage for each backend, including environment variables and operational playbooks.
- [x] Run `dart format`, `dart analyze`, `dart test` (including Docker-backed Redis/Postgres suites), and record validation status.
