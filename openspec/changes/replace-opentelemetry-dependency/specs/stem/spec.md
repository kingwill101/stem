## MODIFIED Requirements

### Requirement: Observability & Control
Stem MUST expose task lifecycle events, metrics, and CLI commands to inspect queues, workers, schedules, retry sets, and dead letters while providing health endpoints for liveness/readiness.

#### Scenario: Tracing uses Dartastic instrumentation
- **GIVEN** a producer enqueues a task or a worker processes an envelope
- **WHEN** Stem emits tracing spans for enqueue, execute, or heartbeat operations
- **THEN** it MUST use `dartastic_opentelemetry` / `dartastic_opentelemetry_api` types exclusively for span creation, propagation, and exporter configuration
