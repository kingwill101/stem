## ADDED Requirements

### Requirement: Generic workflow APIs for typed results
Stem MUST add generic type parameters to workflow definition and helper APIs so callers can declare the result type once and retrieve the same type when polling for completion. `Flow<T>`, `WorkflowScript<T>`, and `WorkflowDefinition<T>` MUST retain backwards compatibility by defaulting to `Object?`, yet allow callers to specify domain models (e.g. `Flow<OrderReceipt>`). The existing waiting helpers (e.g. `StemWorkflowApp.waitForCompletion`) MUST accept an optional decoder and return a typed wrapper (`WorkflowResult<T>`) that includes run metadata (status, runId, raw payload, errors). Decoding MUST only occur when the run finishes successfully; failed/cancelled/timeout states MUST return without invoking the decoder so consumers can inspect the error and decide how to proceed. The behavior MUST remain consistent across in-memory, Redis, Postgres, and SQLite stores because the generic layer only affects API typing, not persistence.

#### Scenario: Completed workflow returns typed value via generics
- **GIVEN** a workflow is registered as `Flow<OrderReceipt>(...)` and finishes with `result = {'email': 'user@example.com', 'total': 42}`
- **AND** a caller invokes `await app.waitForCompletion<OrderReceipt>(runId, decode: OrderReceipt.fromJson)`
- **WHEN** the helper detects `WorkflowStatus.completed`
- **THEN** it MUST decode the stored payload exactly once, return a `WorkflowResult<OrderReceipt>` containing the typed object, and expose the same run metadata (`runId`, status, timestamps) alongside the typed value.

#### Scenario: Failed workflow surfaces error without decoding
- **GIVEN** a workflow run declared as `WorkflowScript<OrderReceipt>` transitions to `WorkflowStatus.failed` with `lastError` populated
- **WHEN** a caller waits via `waitForCompletion<OrderReceipt>(...)`
- **THEN** the helper MUST return a `WorkflowResult<OrderReceipt>` whose status is `failed`, include the raw error metadata, set the typed value to `null`, and MUST NOT call the decoder so clients can choose whether to retry or inspect the raw payload.

#### Scenario: Timeout returns latest non-terminal state
- **GIVEN** a caller sets a timeout while waiting for a generic workflow run that is still `suspended`
- **WHEN** the timeout elapses before the run completes
- **THEN** the helper MUST return a `WorkflowResult<T>` that reflects the current non-terminal status and raw payload (if any) without attempting to decode or mark the run completed, enabling the caller to decide whether to keep waiting or inspect suspension metadata.
