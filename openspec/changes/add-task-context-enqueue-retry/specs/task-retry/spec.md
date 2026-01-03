## ADDED Requirements

### Requirement: TaskRetryPolicy object
The system SHALL expose a `TaskRetryPolicy` object on `TaskOptions` to configure Celery-style retry behavior, including exponential backoff (`backoff`), maximum delay (`backoffMax`), jitter (`jitter`), and default retry delay (`defaultDelay`), with an optional `maxRetries` override.

#### Scenario: Backoff policy applied
- **WHEN** a task with `TaskRetryPolicy(backoff: true, backoffMax: 5m, jitter: true)` fails
- **THEN** the worker schedules the retry using exponential backoff capped at the configured maximum and applies jitter

### Requirement: Auto-retry filters
The system SHALL allow retry policies to specify `autoRetryFor` and `dontAutoRetryFor` filters to match Celery's auto-retry controls.

#### Scenario: Only filtered errors retry
- **WHEN** a task configures `autoRetryFor` and an error outside the allowed list occurs
- **THEN** the worker does not schedule a retry

### Requirement: Per-enqueue retry override
The system SHALL allow per-enqueue overrides of the retry policy so producers or tasks can adjust backoff for a specific invocation.

#### Scenario: Per-enqueue policy override
- **WHEN** a task is enqueued with a retry override that differs from the handler’s `TaskOptions`
- **THEN** the worker uses the override when computing the next retry delay

### Requirement: Retry policy precedence
The system SHALL resolve retry policy using the following precedence: per-enqueue override, then handler `TaskOptions.retryPolicy`, then the worker/global default.

#### Scenario: Precedence resolves to per-enqueue
- **WHEN** all three layers define a retry policy
- **THEN** the per-enqueue override is used to compute the retry delay

### Requirement: TaskContext retry helper
The system SHALL provide `TaskContext.retry` with Celery-style options (countdown/eta/maxRetries/timeLimit/softTimeLimit) to schedule retries explicitly from within a handler.

#### Scenario: retry schedules a new attempt
- **WHEN** a handler calls `context.retry(countdown: 30s)`
- **THEN** the current attempt is marked for retry and a new attempt is scheduled 30 seconds in the future
