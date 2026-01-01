---
title: Programmatic Workers & Enqueuers
sidebar_label: Programmatic Usage
sidebar_position: 2
slug: /workers/programmatic
---

Use Stem's Dart APIs to embed task production and processing inside your
application services. This guide focuses on the two core roles: **producer**
(enqueuer) and **worker**.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Producer (Enqueuer)

<Tabs>
<TabItem value="minimal" label="Minimal">

```dart title="lib/producer.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workers_programmatic.dart#workers-producer-minimal

```

</TabItem>
<TabItem value="redis" label="Redis Broker">

```dart title="lib/producer_redis.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workers_programmatic.dart#workers-producer-redis

```

</TabItem>
<TabItem value="signing" label="Payload Signing">

```dart title="lib/producer_signed.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workers_programmatic.dart#workers-producer-signed

```

</TabItem>
</Tabs>

### Tips

- Always reuse a `Stem` instance rather than creating one per request.
- Use `TaskOptions` to set queue, retries, timeouts, and isolation.
- Add custom metadata via the `meta` argument for observability or downstream
  processing.

## Worker

<Tabs>
<TabItem value="minimal" label="Minimal">

```dart title="bin/worker.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workers_programmatic.dart#workers-worker-minimal

```

</TabItem>
<TabItem value="redis" label="Redis Broker">

```dart title="bin/worker_redis.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workers_programmatic.dart#workers-worker-redis

```

</TabItem>
<TabItem value="advanced" label="Retries & Signals">

```dart title="bin/worker_retry.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workers_programmatic.dart#workers-worker-retry

```

</TabItem>
</Tabs>

### Lifecycle Tips

- Call `worker.shutdown()` on SIGINT/SIGTERM to drain in-flight tasks and emit
  `workerStopping`/`workerShutdown` signals.
- Monitor heartbeats via `StemSignals.workerHeartbeat` or the heartbeat backend
  for liveness checks.
- Use `WorkerLifecycleConfig` to install signal handlers, configure soft/hard
  shutdown timeouts, and recycle isolates after N tasks or memory thresholds.

## Putting It Together

A lightweight service wires the producer and worker into your application
startup:

```dart title="lib/bootstrap.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workers_programmatic.dart#workers-bootstrap

```

Swap the in-memory adapters for Redis/Postgres when you deploy, keeping the API
surface the same.

## Checklist

- Reuse producer and worker objects—avoid per-request construction.
- Inject the `TaskRegistry` from a central module so producers and workers stay
  in sync.
- Capture task IDs returned by `Stem.enqueue` when you need to poll results or
  correlate with your own auditing.
- Emit lifecycle signals (`StemSignals`) and wire logs/metrics early so
  production instrumentation is already in place.
- For HTTP/GraphQL handlers, wrap enqueues in try/catch to surface validation
  errors before tasks hit the queue.

Next, continue with the [Worker Control CLI](./worker-control.md) or explore
[Signals](../core-concepts/signals.md) for advanced instrumentation.
