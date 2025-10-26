---
title: Operations Guide
sidebar_label: Operations
sidebar_position: 1
slug: /operations/guide
---

This guide covers environment configuration, deployment patterns, monitoring, and day-to-day operations for Stem clusters.

## Configuration

Stem reads configuration from environment variables. The most common settings are:

| Variable | Description |
| --- | --- |
| `STEM_BROKER_URL` | Broker connection string (e.g. `redis://localhost:6379`) |
| `STEM_RESULT_BACKEND_URL` | Result backend connection string (`redis://`, `rediss://`, or `postgres://`) |
| `STEM_SCHEDULE_STORE_URL` | Schedule store connection (`redis://`/`postgres://`, defaults to broker when omitted) |
| `STEM_DEFAULT_QUEUE` | Queue name for tasks without explicit routing |
| `STEM_PREFETCH_MULTIPLIER` | Prefetch factor relative to `Worker.concurrency` |
| `STEM_DEFAULT_MAX_RETRIES` | Global fallback retry limit |
| `STEM_HEARTBEAT_INTERVAL` | Worker heartbeat cadence (e.g. `10s`) |
| `STEM_WORKER_NAMESPACE` | Namespace prefix for Redis channels and worker IDs |
| `STEM_REVOKE_STORE_URL` | Override the persistent revoke store (defaults to backend/broker) |
| `STEM_METRIC_EXPORTERS` | Comma separated exporters (`console`, `otlp:http://host:4318/v1/metrics`, `prometheus`) |
| `STEM_OTLP_ENDPOINT` | Default OTLP HTTP endpoint used when exporters omit a target |
| `STEM_SIGNING_KEYS` / `STEM_SIGNING_ACTIVE_KEY` | HMAC signing secrets and active key identifier |
| `STEM_SIGNING_PUBLIC_KEYS` / `STEM_SIGNING_PRIVATE_KEYS` | Ed25519 verification & signing material |
| `STEM_SIGNING_ALGORITHM` | `hmac-sha256` (default) or `ed25519` |
| `STEM_TLS_CA_CERT` | Path to trusted CA bundle for Redis/Postgres/HTTP connections |
| `STEM_TLS_CLIENT_CERT` / `STEM_TLS_CLIENT_KEY` | Mutual TLS credentials for Redis/Postgres/HTTP clients |
| `STEM_TLS_ALLOW_INSECURE` | Set to `true` to bypass TLS verification during debugging |

Keep credentials in a secret manager (Vault, GCP Secret Manager, AWS Secrets Manager) and inject them as environment variables.

For local smoke tests the repository includes `packages/stem_cli/docker/testing/docker-compose.yml`,
which launches Postgres and Redis with ports exposed at `65432`/`56379`. Always
start these containers and export the matching environment variables before
running tests:

```bash
docker compose -f packages/stem_cli/docker/testing/docker-compose.yml up -d postgres redis

export STEM_TEST_REDIS_URL=redis://127.0.0.1:56379
export STEM_TEST_POSTGRES_URL=postgresql://postgres:postgres@127.0.0.1:65432/stem_test
export STEM_TEST_POSTGRES_TLS_URL=$STEM_TEST_POSTGRES_URL
export STEM_TEST_POSTGRES_TLS_CA_CERT=packages/stem_cli/docker/testing/certs/postgres-root.crt
```

With the services running, execute `dart test` in `packages/stem_redis`,
`packages/stem_postgres`, and `packages/stem_cli` to exercise adapters against the
live dependencies. Set `STEM_TLS_CA_CERT` (as shown above) to enable certificate
validation when pointing Stem at the bundled Postgres instance. You can also run
`source packages/stem_cli/_init_test_env` to start the services and export the
variables in one step.

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
- Optional Postgres for the result backend and/or schedule store (Postgres adapters auto-create tables). See `example/postgres_worker` for a Postgres-only setup, `example/redis_postgres_worker` for a Redis broker + Postgres backend hybrid, `example/mixed_cluster` to run Redis- and Postgres-backed workers side by side, or `example/postgres_tls` for a secure Postgres backend using the shared `STEM_TLS_*` configuration.

`examples/microservice` demonstrates an enqueue API and worker process running separately, sharing Redis.

## Process Management

- Package workers as container images with health endpoints (provided by Stem worker observability APIs).
- Use systemd or container orchestrators (Kubernetes, Nomad) to ensure automatic restarts.
- Configure graceful shutdown by catching termination signals and calling `worker.shutdown()`.
- For remote control, revocations, and diagnostics, see the [Worker Control guide](./worker-control.md) covering `stem worker` commands and persistent revoke storage.

## Monitoring & Telemetry

Stem emits metrics and heartbeats via the observability module:

- **Counters**: task started/succeeded/failed/retried, lease renewals, DLQ replays.
- **Histograms**: task execution latency.
- **Gauges**: active isolates, in-flight deliveries, per-queue depth.

Plumb OpenTelemetry exporters into your APM of choice. The CLI command `stem worker status --follow` subscribes to heartbeat streams for live debugging.

Use `stem worker status --once` to dump the latest snapshot from the result backend, or `stem worker status --follow --timeout 60s` to stream updates with a timeout guard. Override connection targets with `--backend` / `--broker`, and adjust expectations with `--heartbeat-interval`.

Run `stem health` as part of deployments to verify broker/back-end connectivity and TLS handshakes before flipping traffic. TLS failures include the endpoint, certificate metadata, and troubleshooting hints.

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

### Security

- **Payload signing**: HMAC-SHA256 remains the default (`STEM_SIGNING_KEYS=primary:<base64 secret>` + `STEM_SIGNING_ACTIVE_KEY=primary`). For asymmetric signing, switch to Ed25519 by setting `STEM_SIGNING_ALGORITHM=ed25519` alongside `STEM_SIGNING_PUBLIC_KEYS` and (for producers) `STEM_SIGNING_PRIVATE_KEYS`. Run `dart run scripts/security/generate_ed25519_keys.dart` to produce ready-to-paste env values. Workers verify signatures automatically and dead-letter tampered payloads; see `docs/process/security-runbook.md` for rotation guidance. Concrete setups for each profile are documented in `docs/process/security-examples.md`.
- **Payload confidentiality**: Encrypt payloads before calling `Stem.enqueue()` when tasks contain sensitive data. The `examples/encrypted_payload` sample demonstrates encrypting with AES-GCM and decrypting inside the worker while keeping payloads opaque in the broker/result backend.
- Producers emit a warning and throw if the signing configuration is incomplete (for example, the active Ed25519 key lacks a private key). Address the log message before attempting to enqueue tasks.
- **TLS bootstrap**: generate a CA plus server/client certificates with
  `scripts/security/generate_tls_assets.sh certs stem.local,redis,api.localhost`.
  The script emits `ca.crt`, `server.crt/server.key`, and `client.crt/client.key`
  so you can secure Redis (set `--port 0 --tls-port 6379 --tls-auth-clients
  yes`) as well as the HTTP enqueue API (set `ENQUEUER_TLS_CERT/KEY`). Once
  certs are installed, switch `redis://` URLs to `rediss://` and point Stem at
  the generated CA and client key material. TLS handshake failures are logged
  with the endpoint and remediation hints; only set
  `STEM_TLS_ALLOW_INSECURE=true` during short-lived debugging.
  * `server.crt`/`server.key` stay with Redis and the HTTPS enqueuer container
    so they can terminate TLS and prove identity to callers.
  * `client.crt`/`client.key` are mounted by producers/workers when mutual TLS
    is enabled, ensuring Redis refuses unauthenticated clients.
  * `ca.crt` is distributed to all Stem processes (via `STEM_TLS_CA_CERT` and
    optionally `ENQUEUER_TLS_CLIENT_CA`) to keep certificate validation enabled
    without trusting arbitrary authorities.
- **Vulnerability scanning**: run `scripts/security/run_vulnerability_scan.sh`
  weekly (or via the scheduled `security-scan.yml` workflow) to execute Trivy
  against the repository. The on-call security owner (`pagerduty://stem-security-primary`)
  triages findings, files issues for High/Critical results, and tracks
  remediation work to closure.

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
  - `stem schedule apply --file schedules.yaml --yes` - validate and upsert definitions from YAML/JSON (use `--dry-run` to preview). The command retries transient optimistic-lock conflicts (five attempts) and preserves last-run metadata when updating live stores.
  - `stem schedule delete <id> --yes` - remove an entry from the active store.
  - `stem schedule dry-run <id> --count 5` - preview upcoming fire times (with jitter) for an existing schedule, or provide `--spec` for ad-hoc evaluation.
- Monitor schedule metadata (next run, last run, jitter) via the `stem observe schedules` summary (includes due/overdue counts, max drift, and per-entry totals) or direct Redis inspection.
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
