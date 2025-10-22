---
title: Core Concepts
slug: /core-concepts
sidebar_position: 0
---

Understand the building blocks that power Stem. These pages explain how tasks,
workers, routing, signals, and canvases fit together so you can reason about
behavior before touching production.

### Feature Highlights

- Queueing and retries with `Stem.enqueue`, `TaskOptions`, and retry
  strategies.
- Worker lifecycle management, concurrency controls, and graceful shutdown.
- Beat scheduler for interval/cron/solar/clocked jobs.
- Canvas primitives (chains, groups, chords) for task composition.
- Lifecycle signals for instrumentation and integrations.
- Declarative routing across queues and broadcast channels.
- Result backends and progress reporting via `TaskContext`.

- **[Tasks & Retries](./tasks.md)** – Task handlers, options, retries, and idempotency guidelines.
- **[Producer API](./producer.md)** – Enqueue tasks with args, metadata, signing, and delays.
- **[Routing](./routing.md)** – Queue aliases, priorities, and broadcast channels.
- **[Signals](./signals.md)** – Lifecycle hooks for instrumentation and integrations.
- **[Canvas Patterns](./canvas.md)** – Chains, groups, and chords for composing work.
- **[Observability](./observability.md)** – Metrics, traces, logging, and lifecycle signals.
- **[Persistence & Stores](./persistence.md)** – Result backends, schedule/lock stores, and revocation storage.
- **[CLI & Control](./cli-control.md)** – Quickly inspect queues, workers, and health from the command line.

Continue with the [Workers guide](../workers/index.md) for operational details.
