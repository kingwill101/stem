## ADDED Requirements
### Requirement: Task Lifecycle Signals
Stem MUST expose signals for key task lifecycle events (publish, received, prerun, postrun, success, failure, retry, revoked).

#### Scenario: task_prerun handler executes
- **GIVEN** a handler registered for `task_prerun` with sender `reports.generate`
- **WHEN** the `reports.generate` task starts executing
- **THEN** the handler MUST receive a payload containing task id, name, args, and worker metadata before the task body runs.

#### Scenario: task_failure signal fires
- **GIVEN** a handler registered for `task_failure`
- **WHEN** a task raises an exception
- **THEN** the handler MUST be invoked with the exception, stack trace, retry info, and envelope metadata.

### Requirement: Worker Lifecycle Signals
Stem MUST emit signals for worker start, ready, and shutdown events, including queue subscriptions.

#### Scenario: worker_ready signal
- **GIVEN** a worker boots successfully
- **WHEN** it begins consuming queues
- **THEN** a `worker_ready` signal MUST fire containing worker id, hostname, queues, and timestamp.

### Requirement: Scheduler Signals
Stem scheduler MUST emit signals when entries become due and after execution (success or failure).

#### Scenario: schedule entry executed
- **GIVEN** a periodic entry runs
- **WHEN** the execution completes
- **THEN** a `schedule_entry_executed` signal MUST fire containing entry id, result status, and duration.

### Requirement: Signal Subscription API
Stem MUST provide a documented API to register/unregister signal handlers with optional sender filtering.

#### Scenario: connect/disconnect handlers
- **GIVEN** a handler connected to `task_success`
- **WHEN** `disconnect` is called
- **THEN** subsequent task successes MUST NOT invoke the handler.
