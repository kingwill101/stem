## ADDED Requirements
### Requirement: Worker Remote Control
Stem MUST expose a control channel allowing operators to issue runtime commands (ping, stats, revoke, shutdown) to one or many workers.

#### Scenario: CLI ping
- **GIVEN** a running worker with control channel enabled
- **WHEN** `stem worker ping` is executed
- **THEN** the worker MUST respond with a `pong` containing its identifier within the configured timeout
- **AND** the CLI MUST surface the response or a timeout error.

#### Scenario: Remote revoke
- **GIVEN** an executing task and the task id
- **WHEN** `stem worker revoke <id>` is issued with `terminate=true`
- **THEN** the worker MUST stop the task, acknowledge the revoke, and persist the revoked id so restarts honour it.

### Requirement: Autoscaling Concurrency
Workers MUST support autoscaling their concurrency between configured minimum and maximum bounds based on workload metrics.

#### Scenario: Scale up on backlog
- **GIVEN** autoscaling enabled with `min=2`, `max=10`
- **AND** queue depth exceeds the scale-up threshold
- **WHEN** the autoscaler evaluates metrics
- **THEN** the worker MUST increase active isolates above 2 (up to the threshold) without restarting the process.

#### Scenario: Scale down when idle
- **GIVEN** autoscaling enabled with `min=2`, `max=10`
- **AND** no tasks have run for the configured idle period
- **WHEN** the autoscaler evaluates metrics
- **THEN** the worker MUST reduce active isolates toward the minimum without dropping below `min` or interrupting in-flight tasks.

### Requirement: Lifecycle Safeguards
Workers MUST provide warm/soft/hard shutdown semantics, max tasks per isolate, and memory recycle thresholds.

#### Scenario: Warm shutdown drains tasks
- **GIVEN** a worker processing tasks
- **WHEN** a warm shutdown command is issued (signal or CLI)
- **THEN** the worker MUST stop fetching new tasks, finish the in-flight work, and exit cleanly.

#### Scenario: Max tasks per isolate triggers recycle
- **GIVEN** `max_tasks_per_isolate` set to 100
- **WHEN** an isolate completes its 100th task
- **THEN** the worker MUST recycle that isolate before executing additional tasks, without impacting other isolates.

#### Scenario: Memory threshold forces recycle
- **GIVEN** `max_memory_per_isolate` configured
- **WHEN** an isolate exceeds the threshold
- **THEN** the worker MUST recycle the isolate after its current task completes and log the event for operators.
