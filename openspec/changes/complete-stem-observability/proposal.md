## Summary
- Finish aligning Stem's observability implementation with the baseline spec requirements.
- Add queue depth and lease renewal metrics, propagate OpenTelemetry traces across enqueue/consume/execute, and surface trace IDs in structured logs.

## Motivation
- The current implementation emits task lifecycle counters, inflight gauges, and latency histograms but omits queue depth and lease renewal metrics promised by the spec.
- Tracing support is stubbed (`StemTracer`) yet unused, leaving the "enqueue→consume→execute" trace path unfulfilled and making it difficult to correlate tasks end-to-end.
- Logs lack trace identifiers, which undermines the spec requirement for trace-aware structured logging and hampers debugging.

## Goals
- Emit queue depth metrics per queue and lease renewal metrics whenever a worker extends a task lease.
- Instrument enqueue/consume/execute with OpenTelemetry spans, propagating context via envelope headers and exposing trace IDs in logs/events.
- Update documentation/examples to reflect the richer telemetry surface and provide quick-start guidance.

## Non-Goals
- Building a full UI dashboard (we only wire telemetry feeds that dashboards could consume).
- Changing broker-specific semantics beyond telemetry hooks (e.g., we will not redesign the Redis Streams lease mechanics).

## Risks & Mitigations
- **Instrumentation overhead**: Use lightweight async-friendly spans and avoid blocking metrics calls; gate expensive operations behind existing environment opt-ins.
- **Header bloat**: Limit trace propagation to the standard W3C context (traceparent) to avoid uncontrolled header growth.
- **Collector compatibility**: Document assumptions (OTLP HTTP default) and keep exporters pluggable so teams can adjust if a collector expects different endpoints.

## Open Questions
- Should we include queue depth metrics for brokers that cannot provide counts efficiently (fallback: report `null`)?
- How should we surface trace IDs when logging isn't configured to include them (e.g., context-based formatters)?
