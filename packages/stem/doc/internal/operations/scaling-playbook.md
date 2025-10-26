---
title: Scaling Playbook
sidebar_label: Scaling
sidebar_position: 3
slug: /operations/scaling
---

This playbook describes how to size workers, plan horizontal scaling, and tune shared infrastructure as Stem adoption grows.

## Capacity Planning

### Worker Concurrency

Stem workers execute tasks in isolates. Baseline formulas:

- `worker isolates = min(cpu_cores * 2, max_isolates)`
- `prefetch = worker isolates * prefetch_multiplier`

Recommendations:

- Start with `concurrency = number of CPU cores`.
- Increase `prefetchMultiplier` only when handlers are I/O-bound and brokers can sustain higher inflight counts.
- Monitor `stem.worker.inflight` gauges to validate isolate utilization.

### Rate Limiting

Use task-level `TaskOptions.rateLimit` to prevent hot handlers from overwhelming downstream systems. The global rate limiter uses shared Redis tokens; ensure the store has low latency and monitor bucket keys for hot spots.

### Visibility Timeouts & Leases

- Set `TaskOptions.visibilityTimeout` long enough for the handler’s worst-case execution.
- Workers automatically renew leases via heartbeats; confirm broker leases match your retry tolerance.

## Horizontal Scaling

### Adding Worker Nodes

1. Provision new instances with the same environment variables (broker/backend URLs, worker queue subscriptions).
2. Deploy the worker container or binary.
3. Verify heartbeats via `stem worker status --once`.
4. Monitor queue depth, DLQ, and retry metrics to ensure load distribution.

### Scaling Beat

- Run at least two beat instances for HA.
- Ensure jitter is enabled to reduce thundering-herd lock contention.
- Observe lock contention metrics (`stem.scheduler.lock.contention`) and adjust jitter or interval accordingly.

### Multi-Tenant Isolation

- Use queue-per-tenant or namespace prefixes in `StemConfig` when isolation is required.
- Rate-limiter keys include the `tenant` header; ensure tenants supply headers so throttling is scoped correctly.

## Infrastructure Tuning

### Redis

- Use clustered Redis for high throughput deployments; isolate Streams/broker data from metrics/locks with logical databases or separate clusters.
- Enable persistence (AOF or RDB) and set up replicas.
- Use `maxmemory-policy` = `noeviction` to avoid dropping in-flight entries.
- Monitor `XINFO` metrics for pending and consumer lag.

### Postgres

- The Postgres result backend and schedule store auto-create their schema. Size
  connection pools per worker (e.g. PgBouncer or pooling in your hosting
  platform) so each worker + beat instance has at least a handful of dedicated
  connections without exhausting server resources.
- Use partitioned tables or TTL jobs for stale task cleanup.

### Networking

- Place workers close to Redis to minimize lease renewal latency.
- Use TLS for broker connections across untrusted networks.

## Testing & Load Simulation

- Use the repository’s `test/` suite as a baseline for unit and integration checks.
- Add soak tests that enqueue large batches of tasks to validate throughput.
- Practice chaos scenarios: kill workers mid-task, drop Redis nodes, ensure the system redelivers tasks.

## Automation Hooks

- Populate metrics dashboards (Grafana/Datadog) with `stem.tasks.*`, `stem.worker.*`, and `stem.dlq.replay` counters.
- Use Infrastructure-as-Code to manage schedule definitions (store YAML/JSON in git, apply via CI using `stem schedule apply`).
- Integrate `stem dlq replay --dry-run` into on-call runbooks to evaluate blast radius before mass replays.

## When to Split Clusters

Split workloads into multiple Stem clusters when:

- You have distinct reliability requirements (e.g., transactional vs. batch jobs).
- Worker isolate counts approach the limits of a single Redis instance.
- Rate limiter state collisions become noisy (e.g., same task names across tenants).

Document cluster ownership, capacity targets, and scaling thresholds in your operations handbook.
