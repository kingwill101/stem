## MODIFIED Requirements

### Requirement: Durable workflow engine with pluggable stores
Stem MUST expose a workflow engine from the core library that executes workflows using a backend-agnostic `WorkflowStore` / `EventBus` interface and ships concrete implementations for Redis, Postgres, and SQLite (via their adapter packages) so developers get identical semantics across environments. The workflow runtime MUST extend the underlying task lease whenever a checkpoint is persisted, and stores MUST write suspension metadata (wake timestamps or event payloads) atomically so resumed steps can continue without re-suspending.

#### Scenario: Checkpoint extends lease and prevents double execution
- **GIVEN** a workflow run processes a long step through `workflow.run`
- **AND** the underlying task lease (visibility timeout) is about to expire
- **WHEN** the step completes and the runtime persists its checkpoint
- **THEN** the runtime MUST call `TaskContext.extendLease` (or equivalent) to push the lease forward
- **AND** the broker MUST NOT deliver the same run to another worker while the first worker continues processing

#### Scenario: Sleep resume uses persisted wake timestamp
- **GIVEN** a step calls `ctx.sleep(const Duration(milliseconds: 200))`
- **AND** the store records the wake timestamp in suspension data
- **WHEN** the runtime dequeues the run after the timestamp has passed
- **THEN** the runtime MUST mark the run resumed without scheduling another sleep
- **AND** the step handler MUST continue to the next step without looping

#### Scenario: Awaited event payload is replayed once
- **GIVEN** a run suspends on `ctx.awaitEvent('shipment.ready')`
- **AND** an event emitter calls `runtime.emit('shipment.ready', payload)`
- **WHEN** the run resumes
- **THEN** the store MUST persist the payload alongside the checkpoint
- **AND** the awaiting step MUST receive the payload exactly once even if the worker crashes after resuming

## ADDED Requirements

### Requirement: Workflow idempotency helper
Stem MUST expose a helper on `FlowContext` (or equivalent runtime context) that returns a stable idempotency key derived from the workflow name, run identifier, and optional scope so developers can reuse it for outbound integrations.

#### Scenario: FlowContext helper provides stable key
- **GIVEN** a workflow step calls `ctx.idempotencyKey('charge')`
- **WHEN** the run restarts after a retry
- **THEN** the helper MUST return the same string value as the prior attempt
- **AND** documentation MUST demonstrate using the helper when calling an external API that expects an idempotency token
