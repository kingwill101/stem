## ADDED Requirements

### Requirement: Task Enqueueing Contracts
The system MUST provide an API to enqueue named tasks with arguments, metadata headers, routing options, priority, max retry limits, and optional future execution timestamps while persisting envelopes durably through pluggable brokers.

#### Scenario: Enqueue task to queue immediately
- **GIVEN** an application calls the Stem client to enqueue task `email.send` with arguments and default queue routing
- **WHEN** the enqueue call completes successfully
- **THEN** the broker MUST persist the envelope with a generated id, attempt counter `0`, configured max retries, and mark the task state as `queued` in the result backend

#### Scenario: Enqueue task with ETA delay
- **GIVEN** an application enqueues task `billing.cleanup` with `notBefore` two minutes in the future
- **WHEN** the broker receives the envelope
- **THEN** the broker MUST hold the envelope in a delayed store until the scheduled time and only present it to consumers after the wall clock is greater than or equal to the requested timestamp

### Requirement: Result Backend Semantics
The result backend MUST persist a canonical record for every task containing status, payload, error metadata, and custom key/value meta so cross-language clients can interpret outcomes consistently.

#### Scenario: Success payload stored canonically
- **GIVEN** a task completes successfully with a JSON-friendly return value
- **WHEN** the worker records completion
- **THEN** the backend MUST store `status: succeeded`, place the return value under `payload`, clear the `error` object, and retain any provided meta entries

#### Scenario: Failure captured with typed error
- **GIVEN** a task throws an exception marked retryable
- **WHEN** the worker records the failure
- **THEN** the backend MUST store `status: failed`, populate `error.type`, `error.message`, `error.stack`, set `error.retryable: true`, and preserve supplied meta information

### Requirement: Worker Execution & Isolation
Workers MUST consume tasks using prefetch limits, execute each task inside a managed isolate context enforcing soft and hard time limits, support heartbeat and lease extension APIs, and acknowledge completion only after successful handler execution.

#### Scenario: Worker processes task within hard limit
- **GIVEN** a worker isolate picks up task `image.resize` with a 30s hard time limit
- **WHEN** the handler completes in under 30 seconds
- **THEN** the worker MUST ACK the delivery, mark the task state as `succeeded`, and release the lease for other consumers

#### Scenario: Hard limit exceeded triggers retry
- **GIVEN** a handler exceeds its configured hard time limit
- **WHEN** the worker terminates the isolate for the overrun task
- **THEN** the worker MUST treat the execution as failed, increment the attempt counter, and invoke the retry pipeline for the envelope

### Requirement: Global Rate Limiting
Workers MUST consult a shared rate limiter store that enforces token-bucket semantics per task (and optional tenant) so limits are respected across all brokers and worker processes.

#### Scenario: Token acquired allows execution
- **GIVEN** task `email.send` has a limit of five executions per second
- **WHEN** a worker requests a token and the bucket has capacity
- **THEN** the limiter MUST grant the token, record the lease in the shared store, and the worker MUST proceed with execution

#### Scenario: Token denied delays execution
- **GIVEN** task `email.send` has exhausted its tokens for the current interval
- **WHEN** a worker requests another token
- **THEN** the limiter MUST deny the request, the worker MUST re-enqueue the envelope with a backoff matching the limiter response, and the result backend MUST record the throttled attempt in task meta

### Requirement: Retry & Dead Letter Handling
The system MUST provide configurable retry strategies with exponential backoff + jitter, detect max-attempt exhaustion, and move failed tasks into a dead letter queue with replay metadata.

#### Scenario: Retry scheduled with backoff
- **GIVEN** a task fails on attempt `1` and has `maxRetries` of `5`
- **WHEN** the retry strategy computes the next delay
- **THEN** the worker MUST re-enqueue the task with attempt incremented by one, scheduled for the computed delay, and record a `retried` state in the result backend

#### Scenario: Max retries moves to DLQ
- **GIVEN** a task fails after exceeding its max retry count
- **WHEN** the worker handles the failure
- **THEN** the system MUST move the envelope to the dead letter queue with failure reason metadata and mark the task state as `failed`

### Requirement: Scheduler (Beat) Operations
The scheduler MUST support cron and interval expressions, per-entry jitter, persistent last-run bookkeeping, and distributed locking so multiple scheduler instances do not double-execute entries.

#### Scenario: Cron entry fires once per schedule
- **GIVEN** a cron entry `cleanup-invoices` scheduled for `0 2 * * *`
- **WHEN** the wall clock reaches 02:00 and the entry is enabled
- **THEN** exactly one scheduler instance MUST enqueue the configured task and update the entry’s `lastRunAt`

#### Scenario: Disabled entry is skipped
- **GIVEN** a schedule entry marked disabled
- **WHEN** the scheduler tick evaluates due entries
- **THEN** the entry MUST remain unsent and the next scheduled time MUST advance without enqueueing a task

### Requirement: Canvas Composition
The system MUST allow chaining, grouping, and chord patterns using the result backend to aggregate task states and emit follow-up tasks when prerequisites succeed.

#### Scenario: Chain executes sequentially
- **GIVEN** a chain `A → B → C` is submitted
- **WHEN** task `A` completes successfully
- **THEN** the system MUST enqueue task `B` with access to `A`’s result and continue until `C` finishes, marking the chain as complete

#### Scenario: Chord callback waits for group completion
- **GIVEN** a chord composed of group `[resize:1, resize:2]` and callback `notify.user`
- **WHEN** every group task reports `succeeded`
- **THEN** the aggregator MUST enqueue the callback exactly once and include the group results payload

### Requirement: Observability & Control
Stem MUST expose task lifecycle events, metrics, and CLI commands to inspect queues, workers, schedules, retry sets, and dead letters while providing health endpoints for liveness/readiness.

#### Scenario: Operator inspects DLQ
- **GIVEN** tasks have accumulated in the dead letter queue
- **WHEN** an operator runs the `stem dlq list` command
- **THEN** the CLI MUST return entries with task id, queue, failure reason, and replay command guidance

#### Scenario: Health endpoint exposes worker status
- **GIVEN** a worker process is running with N active isolates
- **WHEN** a health probe hits the worker’s readiness endpoint
- **THEN** the worker MUST report queue subscriptions, last heartbeat timestamp, and current in-flight counts

#### Scenario: Progress events streamed to observers
- **GIVEN** a task publishes heartbeat and progress updates (e.g., 40% complete)
- **WHEN** an observer subscribes to the Stem event stream
- **THEN** the system MUST publish the progress event via the shared channel and update the task’s result backend meta with the latest heartbeat timestamp and progress value
