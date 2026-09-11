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

Workers and schedulers record their built-in metrics without application-owned
counters. `StemMetrics.instance.snapshot()` exposes process-local aggregates even
when no exporter is configured. Exporting to a network collector remains opt-in.
These observations are not durable exactly-once totals.

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
| `stem.task.age` | Histogram | Time from original enqueue to execution admission, including scheduled delays and retry backoff; not pure queue wait. |
| `stem.worker.concurrency` | Gauge | Current active isolates vs configured concurrency. |
| `stem.worker.inflight` | Gauge | Messages currently reserved by the worker. |
| `stem.workflows.started` | Counter | Successfully created workflow runs. |
| `stem.workflows.succeeded` / `stem.workflows.failed` | Counter | Observed terminal workflow outcomes; retryable failed attempts are not terminal failures. |
| `stem.workflow.duration` | Histogram | Creation-to-success elapsed time, including suspension, scheduling, and retries. |
| `stem.workflow.steps.started` / `stem.workflow.steps.succeeded` / `stem.workflow.steps.failed` | Counter | Observed checkpoint/step execution lifecycle events. |
| `stem.workflow.steps.replayed` | Counter | Cached checkpoint results reused without executing the checkpoint body. |
| `stem.workflow.steps.retried` | Counter | Observed step retry events. |
| `stem.workflow.step.duration` | Histogram | Successful non-replayed step execution durations; suspended steps do not produce false completed durations. |

Workflow series use workflow and stable step names, not run IDs or iteration
numbers. Only exercised metric paths appear in a short local run: a healthy
workload does not manufacture failure or retry measurements.

For an application that already initialized the Dartastic SDK, attach Stem's
events to its existing meter provider:

```dart
// First initialize OTel with the desired metric exporter and reader.
StemMetrics.instance.addExporter(DartasticSdkMetricsExporter());
```

This is a `MetricsExporter` adapter for Stem events, not the SDK's OTLP transport
exporter. Keep `OtlpHttpMetricExporter` and its reader in the SDK configuration;
the adapter supplies the actual Stem measurements. It does not initialize or
shut down the application's SDK. Drain workers, flush metric export, then shut
down the SDK.

The Dartastic adapters retain the existing instrument-name normalization:
`stem.tasks.started` appears as `tasks_started` under instrumentation scope
`stem`. Duration measurements are recorded in milliseconds in Stem's snapshot
and exported in seconds (`unit: s`). For example, `stem.task.duration` appears
as `task_duration`; do not interpret its exported values as milliseconds.

## Tracing

Stem emits enqueue, consume, and execution spans through the application's
Dartastic OpenTelemetry SDK. Initialize the SDK before starting workers;
accessing `StemTracer.instance` alone does not configure an exporter.
`STEM_TRACE_EXPORTER` is not a supported configuration variable.

For a trace-only local receiver using OTLP/gRPC:

```dart
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;

await otel.OTel.initialize(
  serviceName: 'my-stem-app',
  endpoint: 'http://127.0.0.1:4317',
  secure: false,
  spanProcessor: otel.BatchSpanProcessor(
    otel.OtlpGrpcSpanExporter(
      otel.OtlpGrpcExporterConfig(
        endpoint: 'http://127.0.0.1:4317',
        insecure: true,
      ),
    ),
  ),
  enableMetrics: false,
);
```

At application shutdown, drain/close Stem first, then await
`otel.OTel.shutdown()` to flush and close the exporter. The application owns
the SDK lifecycle; closing a worker does not close the global SDK.

After initialization, use Stem's tracing integration:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-tracing

```

Traces include spans for `stem.enqueue`, `stem.consume`, and task execution.
Use attributes (`stem.task`, `stem.queue`, `stem.retry.attempt`) to filter in
your tracing backend.

Canvas fan-out also emits a `stem.canvas.group` composition span. Each group
body's `stem.consume` span links back to that composition span while retaining
its normal task trace parent, so groups and chords remain understandable in
backends that support OpenTelemetry span links.

### Span events and links

With an active recording span, Stem records bounded lifecycle events:

| Event | Recorded when |
| --- | --- |
| `stem.task.retry_scheduled` | A retry or deferred delivery has been successfully published, with task, queue, attempt, and delay attributes. |
| `stem.task.revoked` / `stem.task.cancelled` | Revoked/cancelled delivery acknowledgement succeeds. |
| `stem.lease.renewal_failed` | Renewal fails while the originating delivery's consume span is still recording. |

Events are best-effort diagnostics: they do not initialize the SDK, create
unrelated root spans, or change task outcomes if recording fails. Stem does not
emit an event for every polling tick, heartbeat, or progress update.

Dartastic's active-span wrapper records exception events and Error status for
exceptions escaping execution, so Stem does not duplicate those events. An
explicit `TaskRetryRequest` can therefore mark an attempt's execution span as
Error even when a later attempt succeeds; inspect the retry event and final task
outcome rather than treating every Error span as terminal task failure.

Canvas group consume spans link to the `stem.canvas.group` composition span.
Links are distinct from parent-child relationships. `StemSignals` and workflow
introspection callbacks are also distinct from OTel span events; there is no
automatic mapping of every callback to an event.

### Local viewer without Docker

`otel-desktop-viewer` is a native collector and browser UI. Start an existing
download with:

```bash
otel-desktop-viewer --host 127.0.0.1 --open-browser=false \
  --db ./traces.duckdb --db-max-size 512MB
```

Open `http://127.0.0.1:8000/traces`. OTLP/gRPC listens on `4317`;
OTLP/HTTP listens on `4318`. Match the exporter protocol to the port.
Without `--db`, the viewer's data is in memory and disappears on shutdown.
The database contains telemetry attributes; do not commit it or expose the
unauthenticated local viewer to a public interface.

From the Stem checkout, `sh tool/local_tracing.sh` uses the downloaded binary
and stores data under ignored `build/local-tracing/`. Set `OTEL_VIEWER_BIN` if
the executable is elsewhere. If the viewer is already running, reuse it rather
than starting another collector on the same ports.

Send synthetic task and workflow traces from the repository root:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_TRACES_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
dart run packages/stem/example/observability/local_traces.dart
```

The example reads these settings and explicitly bootstraps and shuts down
tracing. HTTP/protobuf exports go to `/v1/traces` on `4318`; the gRPC bootstrap
above instead uses `4317`. Do not rely on the
metrics-exporter settings above to configure this trace-only example: metric
exporter initialization also owns SDK configuration and should not compete
with explicit application initialization.

The demo includes a retry-to-success, an intentional terminal failure, and
two Canvas fan-out branches. It prints trace IDs for each scenario so the
viewer's Events and Links tabs can be checked against actual worker behavior.

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
    stemLogger.info(
      'workflow.execution',
      fields: {
        'run': event.runId,
        'workflow': event.workflow,
        'step': event.stepId,
        'type': event.type.name,
        'iteration': event.iteration,
      },
    );
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

Import `package:stem/observability.dart` when you need Stem's structured
logging facade. It accepts Stem-owned severity and field types; the underlying
logging dependency is kept out of the public API.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/observability.dart#observability-logging

```

The shared `stemLogger` starts silent by default, so opt in explicitly with
`configureStemLogging(level: StemLogLevel.info, format: StemLogFormat.pretty)`.
When you want machine-oriented output for production log shipping, switch to
`configureStemLogging(format: StemLogFormat.plain)`.

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
