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

- **Counters**: task started/succeeded/failed/retried, DLQ replays.
- **Histograms**: task execution latency.
- **Gauges**: active isolates, in-flight deliveries.

Plumb OpenTelemetry exporters into your APM of choice. The CLI command `stem worker status --follow` subscribes to heartbeat streams for live debugging.

### Logs

- Workers and scheduler use structured logging through `stemLogger`.
- Ensure logs are shipped to a centralized platform (Datadog, Loki, ELK).

### Alerts

- Alert on heartbeat gaps (`stem.worker.inflight` stale data) to detect stalled workers.
- Alert on DLQ growth and retry spikes.
- Alert on scheduler lock contention metrics.

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

- Manage schedules with `stem schedule` CLI subcommands.
- Monitor schedule metadata (next run, last run, jitter) via the `stem observe schedules` report or direct Redis inspection.
- Ensure beat instances share the same Redis namespace to coordinate locks.

## Disaster Recovery

1. Backup Redis persistence (RDB/AOF) regularly.
2. Store schedule definitions and configs in version control (the repo’s `openspec/` change specs act as source of truth).
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
