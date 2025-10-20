## 1. Design & Planning
- [ ] 1.1 Document heartbeat payload schema, publishing interval, and Otel metric set in `design.md`.
- [ ] 1.2 Verify existing middleware hooks support metric emission without blocking hot paths.

## 2. Implementation
- [ ] 2.1 Implement worker heartbeat broadcaster (Redis pub/sub + backend cache) with configurable cadence.
- [ ] 2.2 Add OpenTelemetry metric instruments (counters for started/succeeded/failed, histogram for latency, gauge for inflight isolates).
- [ ] 2.3 Introduce `stem worker status` CLI to subscribe to heartbeat stream and summarize.
- [ ] 2.4 Expose configuration knobs (env + CLI flags) for heartbeat interval and metric exporters.

## 3. Validation
- [ ] 3.1 Unit tests for heartbeat serialization/deserialization.
- [ ] 3.2 Integration test verifying metrics emitted during task execution (use test Otel exporter).
- [ ] 3.3 Update operations guide with monitoring setup instructions.
