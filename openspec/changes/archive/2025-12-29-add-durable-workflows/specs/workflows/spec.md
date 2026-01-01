## ADDED Requirements

### Requirement: Durable workflow engine with pluggable stores
Stem MUST expose a workflow engine from the core library that executes workflows using a backend-agnostic `WorkflowStore` / `EventBus` interface and ships concrete implementations for Redis, Postgres, and SQLite (via their adapter packages) so developers get identical semantics across environments.

#### Scenario: Redis workflow resumes after suspension
- **GIVEN** a workflow run stored in Redis suspends via `ctx.sleep(const Duration(seconds: 5))`
- **WHEN** the configured timer loop reaches the target time
- **THEN** the engine MUST enqueue the resume task once
- **AND** execution MUST continue from the next step without re-running completed checkpoints

#### Scenario: Postgres workflow resumes on event
- **GIVEN** a workflow run using the Postgres store calls `ctx.awaitEvent('order.paid')`
- **AND** an external system invokes `stem emit order.paid {...}`
- **WHEN** the EventBus processes the notification
- **THEN** the workflow run MUST transition to `running` and the callback step MUST receive the event payload

#### Scenario: SQLite workflow persists checkpoints
- **GIVEN** a workflow using the SQLite store completes a step that saves a checkpoint
- **AND** the worker process crashes before the next step executes
- **WHEN** the workflow resumes
- **THEN** the completed step MUST NOT execute again and the run MUST continue from the subsequent step

### Requirement: Workflow CLI operations
Stem CLI MUST expose commands to start, list, inspect, cancel, rewind, and emit workflow events so operators can manage runs without code changes.

#### Scenario: Start workflow from CLI
- **GIVEN** the CLI command `stem wf start order-fulfillment --params '{"orderId":42}'`
- **WHEN** the command succeeds
- **THEN** a new workflow run MUST be created with the provided parameters
- **AND** the CLI MUST print the run identifier

#### Scenario: Inspect workflow run state
- **GIVEN** a workflow run is suspended waiting on topic `payment.received`
- **WHEN** an operator runs `stem wf show <runId>`
- **THEN** the CLI MUST display the current status, cursor, suspension details, and the most recent checkpoint metadata

#### Scenario: Cancel workflow run
- **GIVEN** an operator issues `stem wf cancel <runId>`
- **WHEN** the command completes
- **THEN** the run MUST transition to a cancelled terminal state in the store
- **AND** any pending resume triggers MUST ignore the cancelled run
