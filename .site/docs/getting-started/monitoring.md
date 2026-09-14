---
title: Monitoring Guide
sidebar_label: Monitoring
sidebar_position: 11
slug: /getting-started/monitoring
---

Monitor Stem as a distributed, at-least-once system. Metrics and signals are
telemetry, not exactly-once accounting or business truth.

## Symptom → check → remedy

| Symptom | Check | Remedy |
| --- | --- | --- |
| Queue depth or enqueue-to-start latency rises | Worker heartbeat, concurrency, routing, and broker latency | Restore workers, correct routing, or add capacity; do not blindly increase retries |
| Retry rate rises | `task-retry` payloads, downstream errors, and retry policy | Repair the dependency or bound/reduce retries |
| DLQ volume rises | Sample entries, error class, and payload/schema version | Fix handler/deployment compatibility, then replay selected entries |
| Heartbeats stop | Process health, namespace, broker connectivity, and heartbeat interval | Replace the worker after checking for in-flight work |
| Scheduler drift or missed runs | Schedule store, lock ownership, and broker publish errors | Repair the store/lock path and reconcile schedules |

## Metrics, logs, and signals

Configure `ObservabilityConfig` and `StemMetrics` in application code. Supported
environment names include `STEM_METRIC_EXPORTERS`, `STEM_OTLP_ENDPOINT`,
`STEM_HEARTBEAT_INTERVAL`, `STEM_WORKER_NAMESPACE`, `STEM_SIGNALS_ENABLED`, and
`STEM_SIGNALS_DISABLED`. Exporters are not automatic integrations.

Subscribe to `StemSignals.taskRetry`, `taskSucceeded`, and `taskFailed`, and
include task ID, task name, queue, and run ID in application logs. Signals are
in-process notifications and can be lost on crash; persist audit data
separately.

## CLI probes

The optional `stem_cli` package exposes inspection commands through an
adapter-backed application context:

```bash
stem observe metrics
stem observe queues
stem observe workers
stem worker stats
```

Run `stem <command> --help` for flags in the installed version. Protect
mutating control commands and dashboards with normal operator authentication
and TLS. See [Observe & Operate](./observability-and-ops.md) and
[CLI control](../core-concepts/cli-control.md).
