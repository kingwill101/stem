## MODIFIED Requirements

### Requirement: Durable workflow engine with pluggable stores
Stem MUST expose a workflow engine from the core library that executes workflows using a backend-agnostic `WorkflowStore` / `EventBus` interface and ships concrete implementations for Redis, Postgres, and SQLite (via their adapter packages) so developers get identical semantics across environments. The workflow runtime MUST extend the underlying task lease whenever a checkpoint is persisted, stores MUST write suspension metadata (wake timestamps or event payloads) atomically so resumed steps can continue without re-suspending, and the engine MUST support optional cancellation policies that automatically transition runs to `cancelled` when configured limits are exceeded.

#### Scenario: Run cancels after exceeding max runtime
- **GIVEN** a workflow is started with `maxRunDuration: Duration(minutes: 10)`
- **AND** the run continues executing beyond 10 minutes of wall-clock time
- **WHEN** the runtime evaluates cancellation policies
- **THEN** the run MUST transition to `cancelled`
- **AND** the cancellation reason MUST indicate `maxRunDuration` was exceeded.

#### Scenario: Suspension cancels after exceeding max suspend duration
- **GIVEN** a workflow step suspends with a policy `maxSuspendDuration: Duration(minutes: 5)`
- **AND** the suspension remains unresolved past the allowed duration
- **WHEN** the runtime checks the watcher/due queue
- **THEN** the run MUST cancel instead of re-suspending
- **AND** operators MUST be able to inspect the cancellation reason via CLI.
