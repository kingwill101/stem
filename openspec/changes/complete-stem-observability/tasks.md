## 1. Discovery & Design
- [x] 1.1 Confirm broker support for queue depth exposure (Redis Streams, in-memory) and define behaviour for unsupported adapters.
- [x] 1.2 Design trace propagation scheme (headers, span naming) and logging integration (trace ids in `Context`).

## 2. Implementation
- [x] 2.1 Emit queue depth metrics on a configurable cadence using existing broker APIs; update metrics exporter to handle gauges per queue.
- [x] 2.2 Add lease renewal counters whenever workers extend task visibility and ensure metrics exporter exposes them.
- [x] 2.3 Instrument enqueue/consume/execute with OpenTelemetry spans, propagate trace context via envelopes, and enrich logs with trace IDs.
- [x] 2.4 Update CLI/observability docs and examples (including Docker Compose stack) to explain the new telemetry feeds and trace UI workflow.

## 3. Validation
- [x] 3.1 Unit tests covering queue depth sampling and lease renewal counters.
- [x] 3.2 Integration test validating trace propagation & metrics emission (using in-memory broker/backend with a recording exporter).
- [x] 3.3 `dart analyze`, `dart test`, and `openspec validate complete-stem-observability --strict`.
