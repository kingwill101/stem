---
title: Workers
slug: /workers
sidebar_position: 0
---

Workers pull tasks, manage concurrency, and publish lifecycle signals. Use these
guides to embed workers programmatically and operate them in production.

## Lifecycle overview

Workers connect to the broker, claim deliveries, execute task handlers, and
emit lifecycle signals as they progress (`taskReceived`, `taskPrerun`,
`taskPostrun`, `taskSucceeded`, `taskFailed`). Worker-level signals announce
startup, readiness, heartbeat, and shutdown so dashboards and alerts can track
capacity in near real time.

Shutdowns are cooperative: warm stops fetching new work, soft requests
termination checkpoints, and hard requeues active deliveries. The Worker
Control CLI sends those commands through the same control queues the dashboard
uses, so operational tooling stays consistent.

## Queue subscriptions

Workers can subscribe to:

- **A single queue** (default: `default`) for straightforward deployments.
- **Multiple queues** by configuring a routing subscription (priority queues,
  fan-out, or dedicated lanes per workload).

Queue subscriptions determine which stream shards the worker polls, so keep
queue names stable and document them alongside task registries.

## Concurrency & autoscaling

Workers run multiple tasks in parallel using isolate pools. Configure base
concurrency with `concurrency`, then enable autoscaling to expand/contract
within a min/max range based on backlog and inflight counts.

Prefetch controls how aggressively a worker claims work ahead of execution.
Use smaller values for fairness and larger values for throughput. If you're
using autoscaling, align the prefetch multiplier with your maximum concurrency
so scaling does not starve queues.

## Key environment variables

- `STEM_BROKER_URL` – broker connection string (Redis/Postgres/memory).
- `STEM_RESULT_BACKEND_URL` – durable result backend (optional but recommended).
- `STEM_WORKER_CONCURRENCY` – override concurrency without code changes.
- `STEM_WORKER_PREFETCH` – override prefetch count (or use multiplier).
- `STEM_WORKER_NAMESPACE` – namespace for worker IDs and heartbeats.
- `STEM_CONTROL_NAMESPACE` – override control command namespace.
- `STEM_SIGNING_*` – enable payload signing for tamper detection.

- **[Programmatic Integration](./programmatic-integration.md)** – Wire producers
  and workers inside your Dart services (includes in-memory and Redis examples).
- **[Worker Control CLI](./worker-control.md)** – Inspect, revoke, scale, and
  shut down workers remotely.
- **[Daemonization Guide](./daemonization.md)** – Run workers under systemd,
  launchd, or custom supervisors.

Looking for retry tuning or task registries? See the
[Core Concepts](../core-concepts/index.md).
