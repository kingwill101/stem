## Summary
- Augment Stem's telemetry so worker heartbeats, progress, and throughput metrics are emitted in a structured, pollable channel.
- Provide OpenTelemetry metrics/traces wiring plus CLI commands to tail heartbeat streams for debugging.

## Motivation
- Operators need visibility into isolate health, in-flight counts, and retry spikes to maintain SLOs.
- Current implementation only emits coarse events on an in-process stream with no external sink.

## Goals
- Extend worker runtime to publish structured heartbeat payloads (active isolates, in-flight tasks, lease expirations).
- Integrate OpenTelemetry exporters with counters/histograms for task lifecycle, retries, and replay outcomes.
- Add `stem worker status` CLI (or equivalent) that surfaces heartbeat snapshots and metrics summaries.

## Non-Goals
- Building a full UI dashboard (future change).
- Replacing existing logging infrastructure.

## Risks & Mitigations
- **Telemetry overhead**: Batch heartbeats and allow configurable cadence.
- **Metrics cardinality explosion**: Limit tag sets (queue, task, worker) and document customization hooks.
- **Feature creep**: Focus on essential metrics needed for on-call runbooks.

## Open Questions
- Which exporters should ship by default? (Propose Otel console + Prometheus via optional package.)
- Do we need persistent heartbeat storage or is streaming enough? (Lean toward best-effort streaming + last-sample cache in backend meta.)
