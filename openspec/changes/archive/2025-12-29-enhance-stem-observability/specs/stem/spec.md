## MODIFIED Requirements

### Requirement: Worker Execution & Isolation
Workers MUST emit heartbeat data that external systems can consume without impacting task execution.
#### Scenario: Worker publishes structured heartbeat
- **GIVEN** a worker process with isolate pool size `N`
- **WHEN** the configured heartbeat interval elapses
- **THEN** the worker MUST publish a heartbeat message containing worker id, active isolate count, in-flight deliveries per queue, and last lease renewal timestamp
- **AND** it MUST persist the latest heartbeat snapshot in the result backend meta for monitoring clients

### Requirement: Observability & Control
Stem MUST expose metrics through OpenTelemetry and provide tooling to inspect worker status.
#### Scenario: Metrics exported via OpenTelemetry
- **GIVEN** telemetry is enabled with default configuration
- **WHEN** tasks transition through started, succeeded, failed, retried states
- **THEN** the system MUST emit OpenTelemetry counters and latency histograms tagged by task and queue
- **AND** `stem worker status` MUST surface the latest heartbeat snapshot via CLI with an option to stream live updates
