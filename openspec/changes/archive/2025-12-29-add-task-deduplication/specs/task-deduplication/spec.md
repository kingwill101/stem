## ADDED Requirements

### Requirement: Unique tasks suppress duplicate enqueue
When `TaskOptions.unique` is enabled the enqueue pipeline MUST prevent publishing duplicate envelopes while a matching task is pending by reusing the existing task identifier and recording dedupe metadata.

#### Scenario: Duplicate enqueue reuses existing task id
- **GIVEN** a task definition with `TaskOptions.unique: true`
- **AND** the first enqueue call succeeds and returns task id `abc123`
- **WHEN** a second enqueue with the same arguments occurs before the first task completes
- **THEN** no additional envelope is published
- **AND** the second enqueue call returns `abc123`
- **AND** the result backend metadata records that the duplicate was skipped

### Requirement: Uniqueness window respects TTL and terminal states
The system MUST hold uniqueness for at least the configured `uniqueFor` duration (or a documented default) and release it early once the original task reaches a terminal state so new enqueues can proceed deterministically.

#### Scenario: Lock expires after unique window
- **GIVEN** a task enqueued with `TaskOptions.unique: true` and `uniqueFor: 30s`
- **WHEN** no worker completion signal arrives and 30 seconds elapse
- **THEN** a subsequent enqueue MUST acquire uniqueness and publish a new envelope

#### Scenario: Completion releases uniqueness early
- **GIVEN** a unique task that finishes successfully after 5 seconds
- **WHEN** a new enqueue happens immediately afterwards
- **THEN** the enqueue MUST publish a new envelope without waiting for the remaining unique window
