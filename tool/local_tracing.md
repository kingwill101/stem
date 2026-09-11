# Native local traces

Use the downloaded `otel-desktop-viewer` executable; no Docker, system service,
or global installation is required.

## Start

If a viewer is already running, keep it and open
<http://127.0.0.1:8000/traces>. Do not start a second copy.

For subsequent launches from the repository root:

```sh
sh tool/local_tracing.sh
```

The launcher defaults to
`$HOME/Downloads/otel-desktop-viewer_linux_amd64/otel-desktop-viewer`.
Override it with:

```sh
OTEL_VIEWER_BIN=/path/to/otel-desktop-viewer sh tool/local_tracing.sh
```

This command stays in the foreground; Ctrl+C stops the viewer. It binds all
endpoints to `127.0.0.1`, uses OTLP/gRPC `4317`, OTLP/HTTP `4318`, and browser
port `8000`. It persists telemetry in ignored
`build/local-tracing/traces.duckdb`, with a 512 MB retention limit.

An already-running viewer launched without `--db` still uses memory storage.
The launcher does not reconfigure that process or migrate its existing data.
Trace attributes can contain application data: keep this unauthenticated viewer
local and do not commit/export its database without checking the contents.

## Send actual Stem traces

```sh
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_TRACES_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
dart run packages/stem/example/observability/local_traces.dart
```

Look for the service name printed by the example in the viewer. It runs actual
Stem tasks/workflows with explicitly initialized Dartastic OTLP tracing. The
settings above select HTTP/protobuf; export goes to `/v1/traces` on port `4318`,
not the gRPC receiver on `4317`.
Enqueue, consume, and execution spans are automatic; named checkpoint spans
in the example are manual instrumentation, not a promise that every workflow
checkpoint is automatically traced by the core runtime.

The SDK must start before the worker and shut down after Stem drains.
`StemTracer.instance` does not initialize an exporter, and
`STEM_TRACE_EXPORTER` is not read by Stem.

## Verify correlation, not just ingestion

Use all three viewer tabs, with the same service and time window:

- **Traces:** confirm the producer span is the parent of `stem.enqueue`,
  `stem.consume` references that enqueue span, and task execution is under
  consume. Retried attempts should preserve meaningful causal context, not
  appear as unrelated work. A producer span may end before its consumer;
  use an enclosing operation span when measuring full end-to-end duration.
- **Logs:** select a task log and check its native OTLP trace and span IDs
  against the active execution span. Putting `traceId` in a string attribute
  alone does not establish native log correlation. Worker startup/shutdown
  logs may legitimately have no active trace.
- **Metrics:** check actual task outcome counts, retries, gauges, and histogram
  units. Metrics aggregate operations by bounded attributes such as task name
  and queue; do not add a task/run ID label to every series to simulate
  correlation. Individual trace links require SDK-supported exemplars, not
  arbitrary high-cardinality labels.

One application must own SDK initialization and shutdown. Metric/log exporters
must use that same configured SDK rather than initialize another provider.
Drain workers first, flush all configured signals, then shut down the SDK.

## Profiling versus tracing

- `devtools_profiler` captures sampled CPU stacks and memory snapshots.
- This viewer receives application spans showing causal relationships and
  elapsed durations.
- A long span is not proof that its code was consuming CPU for that time.
- Enabling exporters changes the workload. Compare profiler captures with the
  same telemetry settings; do not compare no-op tracing with full export and
  attribute the entire difference to unrelated runtime changes.

## Events, errors, and fan-out links

The demo prints `retry.traceId`, `failure.traceId`, and `fanout.traceId`:

- Retry: select the first consume span and inspect
  `stem.task.retry_scheduled` with a 100 ms delay. The next attempt succeeds.
- Failure: the execution span has Error status and one SDK `exception` event.
  This failure is intentional, and the demo verifies its terminal task result.
- Fan-out: each branch's consume span has a link to the actual
  `stem.canvas.group` composition span. The link is not a synthetic replacement
  for the parent-child chain.

The SDK also records `TaskRetryRequest` as an exception on the retrying attempt.
That is existing attempt-level tracing behavior, not evidence that the overall
retried task failed. Core cancellation/revocation and lease-failure events are
not triggered by this healthy receiver demo.
