## ADDED Requirements

### Requirement: Workflow idempotency helper
Stem MUST expose a helper on workflow contexts that returns a stable idempotency key derived from the workflow name, run identifier, step, and optional iteration so developers can reuse it for outbound integrations.

#### Scenario: Idempotency key stable across retries
- **GIVEN** a workflow step calls `ctx.idempotencyKey('charge')`
- **AND** the run fails and retries the step
- **WHEN** the step reads the helper again
- **THEN** it MUST return the same string as the previous attempt so external requests can be deduplicated.

#### Scenario: Auto-versioned steps reflect iteration in default key
- **GIVEN** a step is marked `autoVersion: true`
- **AND** the handler calls `ctx.idempotencyKey()` without arguments
- **WHEN** the step executes for iterations `#0` and `#1`
- **THEN** the helper MUST return distinct values that include the iteration suffix, ensuring per-iteration idempotency.
