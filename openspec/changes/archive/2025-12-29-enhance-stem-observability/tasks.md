## 1. Design & Planning
- [x] 1.1 Document heartbeat payload schema, publishing interval, and Otel metric set in `design.md`.
- [x] 1.2 Verify existing middleware hooks support metric emission without blocking hot paths.

## 2. Implementation
- [x] 2.1 Implement worker heartbeat broadcaster (Redis pub/sub + backend cache) with configurable cadence.
- [x] 2.2 Add OpenTelemetry metric instruments (counters for started/succeeded/failed, histogram for latency, gauge for inflight isolates).
- [x] 2.3 Introduce `stem worker status` CLI to subscribe to heartbeat stream and summarize.
- [x] 2.4 Expose configuration knobs (env + CLI flags) for heartbeat interval and metric exporters.

## 3. Validation
- [x] 3.1 Unit tests for heartbeat serialization/deserialization.
- [x] 3.2 Integration test verifying metrics emitted during task execution (use test Otel exporter).
- [x] 3.3 Update operations guide with monitoring setup instructions.
