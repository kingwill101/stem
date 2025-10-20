---
id: operations-guide
title: Operations Guide
sidebar_label: Operations Guide
---

This guide covers environment configuration, deployment patterns, monitoring, and day-to-day operations for Stem clusters.

## Configuration

Stem reads configuration from environment variables. The most common settings are:

| Variable | Description |
| --- | --- |
| `STEM_BROKER_URL` | Broker connection string (e.g. `redis://localhost:6379`) |
| `STEM_RESULT_BACKEND_URL` | Result backend connection string |
| `STEM_SCHEDULE_STORE_URL` | Schedule store (defaults to Redis when omitted) |
| `STEM_DEFAULT_QUEUE` | Queue name for tasks without explicit routing |
| `STEM_PREFETCH_MULTIPLIER` | Prefetch factor relative to `Worker.concurrency` |
| `STEM_DEFAULT_MAX_RETRIES` | Global fallback retry limit |
| `STEM_HEARTBEAT_INTERVAL` | Worker heartbeat cadence (e.g. `10s`) |
| `STEM_WORKER_NAMESPACE` | Namespace prefix for Redis channels and worker IDs |
| `STEM_METRIC_EXPORTERS` | Comma separated exporters (`console`, `otlp:http://host:4318/v1/metrics`, `prometheus`) |
| `STEM_OTLP_ENDPOINT` | Default OTLP HTTP endpoint used when exporters omit a target |

Keep credentials in a secret manager (Vault, GCP Secret Manager, AWS Secrets Manager) and inject them as environment variables.

## Deployment Topologies

### Single Node (Development)

- Broker & backend: in-memory adapters OR local Redis container.
- Processes: one service process running enqueue API + worker + beat.
- Use `examples/monolith_service` to see this topology in action.

### Multi-Service (Production)

- Redis Streams for broker + delay store.
- Redis (same cluster or logical DB) for result backend and lock/rate-limit storage.
- One or more enqueue services publishing envelopes.
- A fleet of worker processes (each with isolate pools).
- One or more beat instances (recommended two for failover).
- Optional Postgres for advanced result backend / schedule storage (future adapters).

`examples/microservice` demonstrates an enqueue API and worker process running separately, sharing Redis.

## Process Management

- Package workers as container images with health endpoints (provided by Stem worker observability APIs).
- Use systemd or container orchestrators (Kubernetes, Nomad) to ensure automatic restarts.
- Configure graceful shutdown by catching termination signals and calling `worker.shutdown()`.

## Monitoring & Telemetry

Stem emits metrics and heartbeats via the observability module:

- **Counters**: task started/succeeded/failed/retried, lease renewals, DLQ replays.
- **Histograms**: task execution latency.
- **Gauges**: active isolates, in-flight deliveries, per-queue depth.

Plumb OpenTelemetry exporters into your APM of choice. The CLI command `stem worker status --follow` subscribes to heartbeat streams for live debugging.

Use `stem worker status --once` to dump the latest snapshot from the result backend, or `stem worker status --follow --timeout 60s` to stream updates with a timeout guard. Override connection targets with `--backend` / `--broker`, and adjust expectations with `--heartbeat-interval`.

Example wiring for OTLP/HTTP metrics export (Jaeger all-in-one via Docker Compose is included in `examples/otel_metrics`):

```dart
import 'package:stem/stem.dart';

Future<void> main() async {
  final observability = ObservabilityConfig(
    namespace: 'prod-us-east',
    heartbeatInterval: const Duration(seconds: 5),
    metricExporters: const [
      'otlp:http://otel-collector:4318/v1/metrics',
    ],
  );

  final worker = Worker(
    broker: await RedisStreamsBroker.connect('redis://redis:6379'),
    registry: taskRegistry,
    backend: await RedisResultBackend.connect('redis://redis:6379'),
    consumerName: 'payments-worker-1',
    observability: observability,
    heartbeatTransport: await RedisHeartbeatTransport.connect(
      'redis://redis:6379',
      namespace: observability.namespace,
    ),
  );

  await worker.start();
}
```

This configuration batches metrics through the OTLP HTTP collector while heartbeats publish over Redis using the same namespace. Set `STEM_METRIC_EXPORTERS="otlp:http://otel-collector:4318/v1/metrics"` in production for parity with the sample code.

### Logs

- Workers and scheduler use structured logging through `stemLogger`.
- Ensure logs are shipped to a centralized platform (Datadog, Loki, ELK).

### Alerts

- Primary SLO alerts are provisioned in Grafana (see `examples/otel_metrics/grafana-alerts.yml`):
  | Signal | Threshold | Severity | Notes |
  | --- | --- | --- | --- |
  | Task success rate | < 99.5% over 15 minutes | Critical | Uses Prometheus query `sum(rate(stem_tasks_succeeded_total[5m]))/sum(rate(stem_tasks_started_total[5m]))` |
  | Task latency p95 | ≥ 3 seconds over 5 minutes | Critical | Samples the duration histogram via `histogram_quantile(0.95, ...)` |
  | Queue depth | ≥ 100 messages sustained for 10 minutes | Warning | Flags backlog growth on default queue via `max(stem_queue_depth)` |
- Configure notification policies in Grafana to page `pagerduty://stem-sre-primary` and post to `#stem-ops`.
- Legacy Prometheus alerts for heartbeat gaps, DLQ age, reclaim spikes, and scheduler skew remain until they are migrated to Grafana.
- Full remediation steps live in `docs/process/observability-runbook.md`.

## Dead Letter Queue Operations

Use the `stem dlq` command group to inspect and remediate failures:

```bash
# List entries
stem dlq list --queue default --limit 20

# Inspect payload
stem dlq show --queue default --id <task-id>

# Replay entries
stem dlq replay --queue default --limit 10 --yes

# Preview replay without executing
stem dlq replay --queue default --limit 5 --dry-run

# Purge confirmed poison messages
stem dlq purge --queue default --yes
```

Replay operations preserve envelope metadata (including attempt counters) and append replay annotations (`lastReplayAt`, `replayCount`) to the result backend so runbooks can determine remediation history.

If you rely on custom brokers, implement the new `replayDeadLetters`, `listDeadLetters`, and `purgeDeadLetters` contract methods to integrate the CLI.

## Scheduler Management

- Manage schedules with `stem schedule` commands:
  - `stem schedule list` - tabular view of id, spec, next/last run, jitter, enabled flag.
  - `stem schedule show <id>` - detailed JSON snapshot for a specific entry.
  - `stem schedule apply --file schedules.yaml --yes` - validate and upsert definitions from YAML/JSON (use `--dry-run` to preview).
  - `stem schedule delete <id> --yes` - remove an entry from the active store.
  - `stem schedule dry-run <id> --count 5` - preview upcoming fire times (with jitter) for an existing schedule, or provide `--spec` for ad-hoc evaluation.
- Monitor schedule metadata (next run, last run, jitter) via the `stem observe schedules` report or direct Redis inspection.
- Ensure beat instances share the same Redis namespace to coordinate locks.

## Disaster Recovery

1. Backup Redis persistence (RDB/AOF) regularly.
2. Store schedule definitions and configs in version control (the repo's `openspec/` change specs act as source of truth).
3. Test worker crash recovery by killing containers mid-task; the at-least-once semantics should redeliver through leases.
4. Document replay thresholds and manual replay commands in your runbook.

## Upgrades

- Run `dart test`, `dart analyze`, and `openspec validate --strict` before deploying.
- Upgrade workers first (they are stateless aside from in-flight tasks), then scheduler, then enqueue services.
- Watch DLQ volume and metrics closely after each rollout.

## Troubleshooting Checklist

| Symptom | Investigation |
| --- | --- |
| Tasks stuck in `running` | Check worker heartbeats, broker inflight count, confirm isolate pool size |
| DLQ grows rapidly | Inspect `stem dlq list`, check task logs, confirm retry strategy |
| Scheduler double firing | Inspect Redis locks, ensure clock sync, review jitter configuration |
| High latency | Review rate limiter configuration, broker health, and isolate CPU saturation |

Keep this guide updated alongside spec changes to ensure operational instructions stay accurate.
