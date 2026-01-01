---
title: Observability
sidebar_label: Observability
sidebar_position: 6
slug: /core-concepts/observability
---

Instrument Stem applications with built-in metrics, traces, and lifecycle
signals.

## Metrics

Stem exports OpenTelemetry metrics via `StemMetrics`. Enable exporters with
environment variables or programmatically.

```bash
export STEM_METRIC_EXPORTERS=otlp:http://localhost:4318/v1/metrics
export STEM_OTLP_ENDPOINT=http://localhost:4318
```

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-metrics

```

Common metric names:

| Metric | Type | Description |
| --- | --- | --- |
| `stem.tasks.started` | Counter | Incremented when a worker begins executing a task. |
| `stem.tasks.succeeded` / `stem.tasks.failed` | Counter | Outcome counters per task/queue. |
| `stem.tasks.retried` | Counter | Number of retries scheduled. |
| `stem.task.duration` | Histogram | Task execution time in milliseconds. |
| `stem.worker.concurrency` | Gauge | Current active isolates vs configured concurrency. |
| `stem.worker.inflight` | Gauge | Messages currently reserved by the worker. |

## Tracing

Wrap enqueue and task handlers with traces by enabling the built-in tracer.

```bash
export STEM_TRACE_EXPORTER=otlp:http://localhost:4318/v1/traces
```

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-tracing

```

Traces include spans for `stem.enqueue`, `stem.consume`, and task execution.
Use attributes (`stem.task`, `stem.queue`, `stem.retry.attempt`) to filter in
your tracing backend.

## Signals

`StemSignals` fire lifecycle hooks for tasks, workers, scheduler events, and
control-plane commands.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-signals

```

## Logging

Use `stemLogger` (Contextual logger) for structured logs.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-logging

```

Workers automatically include attempt, queue, and worker id in log contexts when
`StemSignals` are enabled.

## Health checks

Run the CLI to verify connectivity before deployments:

```bash
stem health --broker "$STEM_BROKER_URL" --backend "$STEM_RESULT_BACKEND_URL"
```

This checks broker/back-end reachability, TLS certificates, and signing
configuration, returning a non-zero exit code on failure.

## Dashboards

A minimal dashboard typically charts:

- Task throughput (`stem.tasks.started`, `stem.tasks.succeeded`, `stem.tasks.failed`).
- Retry delay distribution (`stem.tasks.retried`, `stem.task.duration`).
- Worker heartbeats and concurrency (`stem.worker.concurrency`, `stem.worker.inflight`).
- Scheduler drift (`StemSignals.onScheduleEntryDispatched` drift metrics).

Exporters can be mixed—enable console during development and OTLP in staging/
production. For local exploration, run the `examples/otel_metrics` stack to see
metrics in a collector + Jaeger pipeline.
