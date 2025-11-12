## MODIFIED Requirements

### Requirement: Durable workflow engine with pluggable stores
Stem MUST expose a workflow engine from the core library that executes workflows using a backend-agnostic `WorkflowStore` / `EventBus` interface and ships concrete implementations for Redis, Postgres, and SQLite (via their adapter packages) so developers get identical semantics across environments. The workflow runtime MUST extend the underlying task lease whenever a checkpoint is persisted, and stores MUST write suspension metadata (wake timestamps or event payloads) atomically so resumed steps can continue without re-suspending. Stores MUST provide durable watcher records for event suspensions so payloads are captured and delivered exactly once.

#### Scenario: Event watcher records payload atomically
- **GIVEN** a workflow suspends on `ctx.awaitEvent('shipment.ready')`
- **AND** the store registers a watcher for that topic with the run and step identity
- **WHEN** an external system emits `shipment.ready` with a payload
- **THEN** the store MUST persist the payload with the watcher and mark the run ready to resume within the same atomic operation
- **AND** the runtime MUST dequeue the run and inject the payload via `takeResumeData()` exactly once.

#### Scenario: Watcher cleanup on timeout
- **GIVEN** a watcher is registered with a deadline in the past
- **WHEN** due-run polling detects the elapsed deadline
- **THEN** the store MUST remove the watcher and resume the run with a timeout indication (`TimeoutError` or equivalent) without leaving dangling watcher records.

#### Scenario: Watcher inspection for operators
- **GIVEN** an operator queries runs waiting on `payment.received`
- **WHEN** they call the `runsWaitingOn` (or dedicated watcher listing) API
- **THEN** the store MUST return the pending run identifiers and associated metadata so CLI tooling can display suspended runs.
