## MODIFIED Requirements

### Requirement: Observability & Control
Stem MUST expose metrics through OpenTelemetry and provide tooling to inspect worker status.
#### Scenario: Metrics include queue depth and lease renewals
- **GIVEN** telemetry is enabled with default configuration
- **WHEN** a worker polls queue depth and renews a task lease
- **THEN** the system MUST emit OpenTelemetry metrics for queue depth and lease renewals tagged by queue and worker

#### Scenario: Trace context propagates across enqueue and execution
- **GIVEN** a task is enqueued with tracing enabled
- **WHEN** the worker consumes and executes the task
- **THEN** OpenTelemetry spans MUST capture enqueue, consume, and execute phases in a single trace
- **AND** structured logs MUST include the trace identifier so operators can correlate events
