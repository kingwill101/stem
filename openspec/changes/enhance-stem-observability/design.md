## Overview
Enhance observability by emitting structured heartbeats and metrics that external systems can consume without embedding Stem internals.

### Heartbeat Channel
- Transport: Redis Pub/Sub topic `stem:heartbeat:<namespace>` plus latest snapshot stored in backend meta.
- Payload: `{ workerId, isolateCount, inflight, queues: [{name, inflight}], lastLeaseRenewal, timestamp, version }`.
- Interval: default 10s, configurable via env/CLI.

### Metrics
- Use OpenTelemetry SDK for Dart.
- Instruments:
  - Counter `stem.tasks.started/succeeded/failed/retried` tagged by `task`, `queue`, `worker`.
  - Histogram `stem.task.duration` (ms) tagged by `task`, `queue`.
  - Gauge `stem.worker.inflight` per worker.
  - Counter `stem.replay.count` (linked to DLQ replay change).
- Exporters: console (dev), OTLP HTTP (prod), with Prometheus bridge optional via feature flag.

### CLI Enhancements
- `stem worker status --follow` tails heartbeat stream.
- `stem worker status --once` fetches latest snapshot from backend meta.

### Failure Handling
- Heartbeat publisher should drop messages on failure without crashing the worker.
- CLI should time out after configurable period if no heartbeat seen.

## Open Questions
- Should we include per-task progress samples or only aggregate? Initial plan: include aggregate counts and expose per-task progress via existing event stream.
- How do we authenticate Pub/Sub channels? (Document Redis ACL expectations.)
