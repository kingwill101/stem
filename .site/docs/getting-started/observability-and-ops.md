---
title: Observe & Operate
sidebar_label: Observe & Operate
sidebar_position: 4
slug: /getting-started/observability-and-ops
---

Stem emits telemetry from each configured producer or worker process. Configure
exporters in that process's bootstrap. An OTLP endpoint does not make task
state durable, and setting it does not start a collector for you. The
[experimental dashboard](../core-concepts/dashboard.md) is a separate application.

## Configure

`ObservabilityConfig.fromEnvironment()` reads supported variables including
`STEM_METRIC_EXPORTERS`, `STEM_OTLP_ENDPOINT`, `STEM_HEARTBEAT_INTERVAL`,
`STEM_WORKER_NAMESPACE`, and signal enable/disable variables:

```dart
import 'package:stem/stem.dart';

final observability = ObservabilityConfig.fromEnvironment();
observability.applyMetricExporters();
```

Use the [observability example](https://github.com/kingwill101/stem/tree/master/packages/stem/example/docs_snippets/lib/observability.dart)
for exporter and signal wiring. Metrics can reset when a process restarts.

## Symptom → check → remedy

- **Backlog grows** → check heartbeats, concurrency, routing, and broker
  connectivity → restore workers or add capacity.
- **Retries rise** → inspect the exception and downstream status → repair the
  dependency or classify permanent errors as non-retryable.
- **DLQ grows** → inspect representative payloads and reasons → deploy a
  compatible handler/schema, then replay deliberately.
- **Heartbeats disappear** → check process health, broker access, namespace,
  and TTL → replace the worker after checking for in-flight work.
- **Workflow is suspended** → inspect run state and waiter topic → emit the
  matching event or cancel according to policy.

## CLI operations

Install the separate CLI as a development dependency:

```bash
dart pub add --dev stem_cli
dart run stem_cli:stem --help
```

In the commands below, `stem` means that executable; replace it with
`dart run stem_cli:stem` when using the project-local installation. The CLI
resolves the broker and store URLs configured through environment variables or
command flags. Point it at the same namespace and stores as your application.
Task metadata inspection additionally needs your registry configuration; the
CLI cannot discover arbitrary Dart task bodies from a queue.

```bash
stem health --broker "$STEM_BROKER_URL" --backend "$STEM_RESULT_BACKEND_URL" --json
stem worker ping
stem worker inspect
stem worker stats
stem worker status
stem observe metrics
stem observe queues
stem observe workers
stem dlq list --queue default
stem routing dump
stem schedule list
stem wf list
```

`health` checks broker/backend connectivity, not whether an application task
can complete. Combine it with a representative enqueue-to-result smoke test.

Use `stem <command> --help` for required options. Protect replay, purge,
revoke, shutdown, pause, schedule mutation, and workflow cancellation with
operator authentication and an audit trail.

See [CLI control](../core-concepts/cli-control.md) and
[workflow troubleshooting](../workflows/troubleshooting.md).
