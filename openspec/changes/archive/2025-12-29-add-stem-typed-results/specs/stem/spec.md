## ADDED Requirements

### Requirement: Typed task completion helpers
Stem MUST expose typed helpers for observing individual task results so callers can await completion and receive the decoded payload together with the raw `TaskStatus`. Helpers MUST accept an optional decoder to transform the backend payload before returning it, default to a simple cast when no decoder is provided, and refrain from invoking the decoder when the task is not `TaskState.succeeded`.

#### Scenario: Completed task decodes payload
- **GIVEN** a producer enqueues `billing.capture` using a `TaskDefinition` with result type `ChargeReceipt`
- **AND** the task handler stores `{'amount': 42}` as its payload
- **WHEN** the caller waits via `stem.waitForTask<ChargeReceipt>(taskId, decode: ChargeReceipt.fromJson)`
- **THEN** the helper MUST decode the payload exactly once, return a typed wrapper containing the `ChargeReceipt`, and include the underlying `TaskStatus` metadata for inspection

#### Scenario: Failed task skips decoder
- **GIVEN** a task transitions to `TaskState.failed` with `TaskError.retryable == false`
- **WHEN** a caller awaits it through the typed helper
- **THEN** the helper MUST return a wrapper whose `status.state == failed`, set the typed value to `null`, expose the raw `TaskError`, and MUST NOT invoke the decoder so the caller can decide how to handle the failure

#### Scenario: Primitive payload uses default cast
- **GIVEN** a task succeeds with payload `'ok'`
- **WHEN** the caller requests `stem.waitForTask<String>(taskId)` without a decoder
- **THEN** the helper MUST cast the payload to `String` and return it, raising a descriptive error only if the stored payload is incompatible with the requested type
