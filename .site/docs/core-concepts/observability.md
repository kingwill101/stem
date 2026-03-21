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

When you inspect `TaskPostrunPayload` or `TaskSuccessPayload` directly, prefer
`payload.resultJson(...)`, `payload.resultVersionedJson(...)`, or
`payload.resultAs(codec: ...)` over manual
`payload.result as Map<String, Object?>` casts.
For workflow lifecycle signals, prefer
`payload.metadataJson('key', ...)`,
`payload.metadataVersionedJson('key', ...)`, or
`payload.metadataAs('key', codec: ...)` over manual
`payload.metadata['key'] as Map<String, Object?>` casts. If the entire
metadata map is one DTO, use `payload.metadataPayloadJson(...)`,
`payload.metadataPayloadVersionedJson(...)`, or
`payload.metadataPayloadAs(codec: ...)` instead.

## Workflow Introspection

Workflow runtimes can emit execution events (started/completed/failed/retrying)
for both flow steps and script checkpoints through a
`WorkflowIntrospectionSink`. Use it to publish workflow telemetry or bridge to
your own tracing/logging systems.

```dart
class LoggingWorkflowIntrospectionSink implements WorkflowIntrospectionSink {
  @override
  Future<void> recordStepEvent(WorkflowStepEvent event) async {
    stemLogger.info('workflow.execution', {
      'run': event.runId,
      'workflow': event.workflow,
      'step': event.stepId,
      'type': event.type.name,
      'iteration': event.iteration,
    });
  }
}
```

When a completed step or checkpoint carries a DTO payload, prefer
`event.resultJson(...)`, `event.resultVersionedJson(...)`, or
`event.resultAs(codec: ...)` over manual
`event.result as Map<String, Object?>` casts.
Step and runtime introspection events also expose typed metadata helpers via
`event.metadataJson('key', ...)`, `event.metadataVersionedJson('key', ...)`,
`event.metadataAs('key', codec: ...)`, `event.metadataPayloadJson(...)`, and
`event.metadataPayloadVersionedJson(...)`.
When worker events carry structured `data`, prefer `event.dataJson(...)`,
`event.dataVersionedJson(...)`, or `event.dataAs(codec: ...)` over manual
`event.data!['key']` casts. For completed control commands, use
`payload.responseJson(...)`, `payload.responseVersionedJson(...)`,
`payload.responseAs(codec: ...)`, `payload.errorJson(...)`,
`payload.errorVersionedJson(...)`, or `payload.errorAs(codec: ...)` instead of
walking raw `response` / `error` maps.
Persisted worker heartbeats expose the same typed decode path on `extras` via
`heartbeat.extrasJson(...)`, `heartbeat.extrasVersionedJson(...)`, and
`heartbeat.extrasAs(codec: ...)`.

## Logging

Use `stemLogger` (Contextual logger) for structured logs.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-logging

```

For local development, switch the shared logger to colored terminal output with
`configureStemLogging(format: StemLogFormat.pretty)`. Keep the default plain
formatter for production log shipping and machine parsing.

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
production. For local exploration, run the
`packages/stem/example/otel_metrics` stack to see metrics in a collector +
Jaeger pipeline.
