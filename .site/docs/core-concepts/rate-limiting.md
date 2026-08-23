---
title: Rate Limiting
sidebar_label: Rate Limiting
sidebar_position: 4
slug: /core-concepts/rate-limiting
---

Stem supports per-task rate limits via `TaskOptions.rateLimit` and a pluggable
`RateLimiter` interface. This lets you throttle hot handlers with a shared
Redis-backed limiter or custom driver.

Stem also supports group-scoped rate limits with `TaskOptions.groupRateLimit`
for shared quotas across multiple task types/tenants.

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
<TabItem value="app" label="Bootstrap StemApp">

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

## Rate limit values

In Dart code, use the typed `RateLimit` value object:

```dart
const TaskOptions(
  rateLimit: RateLimit.perMinute(100),
  groupRateLimit: RateLimit.perSecond(5),
)
```

String values remain supported at JSON/YAML and environment-configuration
boundaries:

- `10/s` — 10 tokens per second
- `100/m` — 100 tokens per minute
- `500/h` — 500 tokens per hour

`groupRateLimit` uses the same syntax. The worker receives a validated
`RateLimit` value rather than parsing strings during task execution.

## How it works

- The worker asks the configured limiter to acquire the typed `rateLimit`.
- The worker asks the `RateLimiter` for an acquire decision.
- If denied, the task is retried with backoff and `rateLimited=true` metadata.
- Retry delays come from the limiter `retryAfter` if provided, otherwise the
  worker’s retry strategy.
- If granted, the task executes immediately.

## Group rate limiting

Group rate limits share a limiter bucket across related tasks.

- `groupRateLimit`: limiter policy for the shared group bucket
- `groupRateKey`: optional static key (if omitted, Stem resolves from header)
- `groupRateKeyHeader`: header used when `groupRateKey` is not set
  (default: `tenant`)
- `groupRateLimiterFailureMode` (default: `failOpen`):
  - `failOpen`: continue execution if limiter backend fails
  - `failClosed`: requeue/retry when limiter backend fails

```dart title="lib/rate_limiting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/rate_limiting.dart#rate-limit-group-task-options

```

## Redis-backed limiter example

The `packages/stem/example/rate_limit_delay` demo uses the shipped Redis
token-bucket limiter. It:

- shares tokens across multiple workers,
- uses Redis server time and an atomic Lua refill/acquire operation,
- reschedules denied tasks with retry metadata.

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

The Redis limiter is constructed with `RedisRateLimiter.connect(...)` from
`stem_redis`. `stem_postgres` provides the equivalent
`PostgresRateLimiter.connect(...)`; it uses a server-clock token bucket with a
row lock inside one transaction.

## Tips

- Use shared Redis for global limits across worker processes.
- Keep the rate limit key stable (by default it uses task name + tenant).
- Start with generous limits, then tighten after observing throughput.

## Next steps

- See [Tasks & Retries](./tasks.md) for other `TaskOptions` knobs.
- Use [Observability](./observability.md) to instrument rate-limited flows.
