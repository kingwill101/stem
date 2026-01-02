---
title: Rate Limiting
sidebar_label: Rate Limiting
sidebar_position: 4
slug: /core-concepts/rate-limiting
---

Stem supports per-task rate limits via `TaskOptions.rateLimit` and a pluggable
`RateLimiter` interface. This lets you throttle hot handlers with a shared
Redis-backed limiter or custom driver.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Quick start

<Tabs>
<TabItem value="task-options" label="Task Options">

```dart title="lib/shared.dart" file=<rootDir>/../packages/stem/example/rate_limit_delay/lib/shared.dart#rate-limit-task-options

```

</TabItem>
<TabItem value="worker-wiring" label="Worker Wiring">

```dart title="bin/worker.dart" file=<rootDir>/../packages/stem/example/rate_limit_delay/bin/worker.dart#rate-limit-worker

```

</TabItem>
<TabItem value="producer-enqueue" label="Producer Enqueue">

```dart title="bin/producer.dart" file=<rootDir>/../packages/stem/example/rate_limit_delay/bin/producer.dart#rate-limit-producer-enqueue

```

</TabItem>
</Tabs>

### Docs snippet (in-memory demo)

<Tabs>
<TabItem value="task" label="Define a rate-limited task">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-task-options

```

</TabItem>
<TabItem value="limiter-config" label="Limiter config + state">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-demo-limiter-config

```

</TabItem>
<TabItem value="limiter-acquire" label="Limiter acquire decision">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-demo-limiter-acquire

```

</TabItem>
<TabItem value="worker" label="Wire worker with rate limiter">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-worker

```

</TabItem>
<TabItem value="producer" label="Enqueue with tenant header">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-producer

```

</TabItem>
<TabItem value="registry" label="Bootstrap StemApp">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-demo-registry

```

</TabItem>
<TabItem value="start" label="Start worker">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-demo-worker-start

```

</TabItem>
<TabItem value="stem" label="Create Stem client">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-demo-stem

```

</TabItem>
<TabItem value="enqueue" label="Enqueue demo task">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-demo-enqueue

```

</TabItem>
<TabItem value="shutdown" label="Shutdown cleanly">

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-demo-shutdown

```

</TabItem>
</Tabs>

Run the `rate_limit_delay` example for a full demo:

- `packages/stem/example/rate_limit_delay`

## Rate limit syntax

`rateLimit` accepts short strings like:

- `10/s` — 10 tokens per second
- `100/m` — 100 tokens per minute
- `500/h` — 500 tokens per hour

## How it works

- The worker parses `rateLimit` for each task.
- The worker asks the `RateLimiter` for an acquire decision.
- If denied, the task is retried with backoff and `rateLimited=true` metadata.
- Retry delays come from the limiter `retryAfter` if provided, otherwise the
  worker’s retry strategy.
- If granted, the task executes immediately.

## Redis-backed limiter example

The `example/rate_limit_delay` demo ships a Redis fixed-window limiter. It:

- shares tokens across multiple workers,
- logs when a token is granted or denied,
- reschedules denied tasks with retry metadata.

Inspect it here:

```dart title="lib/rate_limiter.dart" file=<rootDir>/../packages/stem/example/rate_limit_delay/lib/rate_limiter.dart#rate-limit-redis-limiter

```

## Observability

When a task is rate limited:

- `context.meta['rateLimited']` is set on the retry attempt,
- `taskRetry` signals include retry metadata,
- worker logs show the limiter decision (if you log it).

## Keying behavior

The worker uses a default rate-limit key of:

```
<taskName>:<tenant>
```

If no tenant header is set, it defaults to `global`. Add a `tenant` header when
enqueuing tasks to enforce per-tenant limits.

## Redis limiter wiring

The `rate_limit_delay` example reads `STEM_RATE_LIMIT_URL` to point the limiter
at Redis. Use a dedicated Redis DB or key prefix to keep limiter state isolated
from your broker/result backend.

```dart title="lib/shared.dart" file=<rootDir>/../packages/stem/example/rate_limit_delay/lib/shared.dart#rate-limit-redis-connector

```

## Tips

- Use shared Redis for global limits across worker processes.
- Keep the rate limit key stable (by default it uses task name + tenant).
- Start with generous limits, then tighten after observing throughput.

## Next steps

- See [Tasks & Retries](./tasks.md) for other `TaskOptions` knobs.
- Use [Observability](./observability.md) to instrument rate-limited flows.
