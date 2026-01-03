## ADDED Requirements

### Requirement: TaskContext enqueue helpers
The system SHALL expose enqueue helpers on `TaskContext` that schedule new tasks from within a handler using the same semantics as `Stem.enqueue` / `Stem.enqueueCall` and accept Celery-style enqueue options.

#### Scenario: Enqueue from inline task handler
- **WHEN** a handler calls `context.enqueue('tasks.child', args: {'id': '123'})`
- **THEN** a new task is published and a task id is returned to the handler

#### Scenario: Spawn alias uses enqueue semantics
- **WHEN** a handler calls `context.spawn('tasks.child', args: {...})`
- **THEN** the task is enqueued using the same defaults and overrides as `context.enqueue`

### Requirement: TaskInvocationContext enqueue helpers
The system SHALL expose enqueue helpers on `TaskInvocationContext` so isolate entrypoints can schedule tasks without direct access to a `Stem` instance, using the same option surface as `TaskContext.enqueue`, including the full fluent builder API.

#### Scenario: Enqueue from isolate entrypoint
- **WHEN** an isolate entrypoint calls `context.enqueue('tasks.child', args: {'id': '123'})`
- **THEN** the worker enqueues the task and returns a task id to the entrypoint

#### Scenario: Fluent enqueue from isolate entrypoint
- **WHEN** an isolate entrypoint uses the `TaskEnqueueBuilder` through `context.enqueueBuilder(...)`
- **THEN** the builder options are applied and the task is enqueued successfully

### Requirement: FunctionTaskHandler inline execution toggle
The system SHALL allow `FunctionTaskHandler` to opt out of isolate execution so inline closures can be used safely when they cannot be transferred across isolate boundaries.

#### Scenario: Inline handler execution
- **WHEN** a handler is created with `FunctionTaskHandler(..., runInIsolate: false)` (or equivalent inline factory)
- **THEN** the entrypoint executes in the worker isolate without isolate handoff

### Requirement: Enqueue scheduling options parity
The system SHALL support Celery-style scheduling options when enqueuing from a task context, including `countdown`, `eta`, and `expires`.

#### Scenario: Countdown scheduling
- **WHEN** a handler calls `context.enqueue('tasks.child', countdown: 30s)`
- **THEN** the task is scheduled with a `notBefore` timestamp at least 30 seconds in the future

#### Scenario: ETA scheduling
- **WHEN** a handler calls `context.enqueue('tasks.child', eta: 2026-01-03T10:00:00Z)`
- **THEN** the task is scheduled with a `notBefore` timestamp equal to the ETA

#### Scenario: Expired task is rejected
- **WHEN** a handler calls `context.enqueue('tasks.child', expires: 2026-01-03T10:00:00Z)` and the task is delivered after the expiry
- **THEN** the worker marks the task as expired and does not execute the handler

### Requirement: Enqueue execution limit overrides
The system SHALL accept Celery-style execution limit overrides (`timeLimit`, `softTimeLimit`) during enqueue and apply them to the scheduled task.

#### Scenario: Time limit override
- **WHEN** a handler calls `context.enqueue('tasks.child', timeLimit: 30s)`
- **THEN** the task executes with a hard time limit of 30 seconds

#### Scenario: Soft time limit override
- **WHEN** a handler calls `context.enqueue('tasks.child', softTimeLimit: 10s)`
- **THEN** the task executes with a soft time limit of 10 seconds

### Requirement: Enqueue routing options parity
The system SHALL accept Celery-style routing options during enqueue, including `queue`, `exchange`, `routingKey`, and `priority`, and propagate them to broker adapters when supported.

#### Scenario: Queue and priority routing
- **WHEN** a handler calls `context.enqueue('tasks.child', queue: 'critical', priority: 9)`
- **THEN** the task is published to the `critical` queue with priority 9

#### Scenario: Exchange and routing key propagation
- **WHEN** a handler calls `context.enqueue('tasks.child', exchange: 'billing', routingKey: 'invoices')`
- **THEN** the enqueue request includes the exchange and routing key metadata for broker adapters

### Requirement: Enqueue metadata options parity
The system SHALL accept Celery-style metadata options (`headers`, `shadow`, `replyTo`) and propagate them to broker adapters.

#### Scenario: Headers preserved
- **WHEN** a handler calls `context.enqueue('tasks.child', headers: {'x-trace-id': 'abc'})`
- **THEN** the enqueued task includes the provided headers

#### Scenario: Default header/meta propagation
- **WHEN** a handler calls `context.enqueue('tasks.child')` without explicit headers or metadata
- **THEN** the enqueued task inherits the current task’s headers and metadata by default

#### Scenario: Shadow name stored
- **WHEN** a handler calls `context.enqueue('tasks.child', shadow: 'shadow.name')`
- **THEN** the enqueued task stores the shadow name for observability

#### Scenario: Reply-to metadata stored
- **WHEN** a handler calls `context.enqueue('tasks.child', replyTo: 'reply.queue')`
- **THEN** the enqueue request propagates the reply-to value to adapters that support direct replies

### Requirement: Enqueue serialization options parity
The system SHALL accept Celery-style serialization options (`serializer`, `compression`) and apply them to payload encoding when supported.

#### Scenario: Serializer override
- **WHEN** a handler calls `context.enqueue('tasks.child', serializer: 'json')`
- **THEN** the payload is encoded using the requested serializer when available

#### Scenario: Compression override
- **WHEN** a handler calls `context.enqueue('tasks.child', compression: 'gzip')`
- **THEN** the payload is compressed using the requested compression when available

### Requirement: Enqueue publish retry parity
The system SHALL accept Celery-style publish options during enqueue, including `retry`, `retryPolicy`, and optional publish connection/producer overrides, applying them when supported by the adapter.

#### Scenario: Publish retry enabled
- **WHEN** a handler calls `context.enqueue('tasks.child', retry: true, retryPolicy: {...})`
- **THEN** the enqueue operation retries publish according to the provided policy

#### Scenario: Publish connection override
- **WHEN** a handler calls `context.enqueue('tasks.child', publishConnection: {...})`
- **THEN** the adapter uses the provided connection override when publishing, if supported

#### Scenario: Publish producer override
- **WHEN** a handler calls `context.enqueue('tasks.child', producer: {...})`
- **THEN** the adapter uses the provided producer override when publishing, if supported

### Requirement: Enqueue callbacks parity
The system SHALL accept Celery-style `link` and `linkError` callbacks when enqueuing from a task context, enqueuing the linked tasks on success or failure.

#### Scenario: link callback on success
- **WHEN** a handler enqueues a task with `link` callbacks
- **THEN** the linked tasks are enqueued after the original task succeeds

#### Scenario: linkError callback on failure
- **WHEN** a handler enqueues a task with `linkError` callbacks
- **THEN** the linked tasks are enqueued after the original task fails

### Requirement: Ignore-result parity
The system SHALL accept an `ignoreResult` enqueue option that suppresses result persistence for the enqueued task.

#### Scenario: ignoreResult skips result storage
- **WHEN** a handler calls `context.enqueue('tasks.child', ignoreResult: true)`
- **THEN** the result backend does not persist the task result payload

### Requirement: Task id override
The system SHALL accept a `taskId` override during enqueue to match Celery's `task_id` option.

#### Scenario: Custom task id
- **WHEN** a handler calls `context.enqueue('tasks.child', taskId: 'custom-id-123')`
- **THEN** the published task uses the provided id

#### Scenario: Task id overwrite
- **WHEN** a handler calls `context.enqueue('tasks.child', taskId: 'custom-id-123')` and a previous task result exists for the same id
- **THEN** the enqueue is accepted and the new task result overwrites the previous stored state

### Requirement: Lineage propagation for context enqueues
The system SHALL include lineage metadata when enqueuing from a task context, capturing at least parent and root task identifiers, and SHALL allow explicit overrides. The system SHALL also support an `addToParent` toggle that controls lineage propagation.

#### Scenario: Parent/root metadata defaults
- **WHEN** a handler calls `context.enqueue(...)` with no lineage overrides
- **THEN** the enqueued task metadata includes `stem.parentTaskId` set to the current task id
- **AND** `stem.rootTaskId` is set to the current task id unless a root id is already present

#### Scenario: Lineage metadata override
- **WHEN** a handler calls `context.enqueue(...)` with explicit lineage metadata
- **THEN** the explicit values are preserved

#### Scenario: addToParent disables propagation
- **WHEN** a handler calls `context.enqueue(...)` with `addToParent: false`
- **THEN** no parent/root lineage metadata is added automatically
