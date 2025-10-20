## Design Considerations

### Queue Depth Metrics
- **Source**: leverage `Broker.pendingCount(queue)` which already exists for Redis Streams and in-memory adapters. For adapters returning `null`, report a `stem.queue.depth` gauge with `value = double.nan` or skip emission to avoid misleading data.
- **Cadence**: reuse the worker heartbeat loop to publish queue depth metrics per subscribed queue, avoiding additional timers.
- **Tags**: include `queue`, `worker`, and `namespace` for alignment with other metrics.

### Lease Renewal Metrics
- Increment `stem.lease.renewed` counter whenever `Worker._startLeaseTimer` extends a lease or handlers call `context.extendLease`. Provide tags (`queue`, `worker`, `task`).
- Consider adding a gauge for `stem.lease.time_remaining` if we want richer telemetry, but start with counters per spec.

### Trace Propagation
- Adopt W3C trace context: store `traceparent` (and optionally `tracestate`) headers on the `Envelope`.
- On `Stem.enqueue`, start a span (`stem.enqueue`) and inject the active context into the envelope headers before publishing.
- Worker consumption should extract the context, start a child span (`stem.consume`) and a nested `stem.execute.<task>` span around the handler.
- Loggers should append `traceId` and `spanId` to the `Context` so structured logs contain the trace linkage.

### Backward Compatibility
- Maintain existing metrics JSON schema for CLI outputs; add new fields without breaking consumers.
- Ensure trace headers don’t break existing envelope serialization (headers already allow arbitrary strings).
- Document new environment variables where applicable (e.g., `STEM_QUEUE_METRIC_INTERVAL`).
