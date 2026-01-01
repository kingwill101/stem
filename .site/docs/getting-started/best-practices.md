---
title: Best Practices
sidebar_label: Best Practices
sidebar_position: 9
slug: /getting-started/best-practices
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

These guidelines help keep task systems reliable and observable as you scale.
They are framework-agnostic and apply directly to Stem.

## Task design

- Keep task arguments small and serializable.
- Store large payloads in object storage and pass references instead.
- Make tasks idempotent; assume retries can happen.
- Wrap enqueue + state changes in a transaction or outbox pattern when
  interacting with databases.
- Prefer deterministic task names and queues for routing clarity.
- Surface structured metadata for tracing and auditing.

<Tabs>
<TabItem value="task" label="Define a task">

```dart title="lib/best_practices.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/best_practices.dart#best-practices-task

```

</TabItem>
<TabItem value="enqueue" label="Typed enqueue">

```dart title="lib/best_practices.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/best_practices.dart#best-practices-enqueue

```

</TabItem>
</Tabs>

## Error handling

- Treat transient failures as retryable; use explicit backoff policies.
- Fail fast on validation errors to avoid wasted retries.
- Send poison-pill tasks to a DLQ and fix root causes before replaying.

```dart title="lib/workers_programmatic.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workers_programmatic.dart#workers-worker-retry

```

## Concurrency & load

- Start with conservative concurrency and scale up with metrics.
- Embrace concurrency by running more worker processes instead of single
  hot loops.
- Use rate limits for hot handlers or fragile downstreams.
- Avoid long-running inline loops without heartbeats or progress signals.

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-task

```

## Observability

- Emit lifecycle signals early so you can build dashboards from day one.
- Track queue depth, retry rates, and DLQ volume as leading indicators.
- Correlate task IDs with business logs for easier incident response.

```dart title="lib/signals.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/signals.dart#signals-configure

```

## Operations

- Separate environments with namespaces and credentials.
- Bake health checks into deploy pipelines.
- Automate rotation of signing keys and TLS certificates.

```dart title="lib/production_checklist.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/production_checklist.dart#production-signing-config

```

## Terminology clarity

- **Task**: a unit of work executed by a worker.
- **Queue**: the channel tasks are routed through.
- **Worker**: the process that consumes tasks and executes handlers.
- **Backend**: the store for task results and group state.

## Next steps

- [Observability & Ops](./observability-and-ops.md)
- [Production Checklist](./production-checklist.md)
- [Tasks & Retries](../core-concepts/tasks.md)
