---
title: Rate Limiting
sidebar_label: Rate Limiting
sidebar_position: 4
slug: /core-concepts/rate-limiting
---

Stem supports per-task rate limits via `TaskOptions.rateLimit` and a pluggable
`RateLimiter` interface. This lets you throttle hot handlers with a shared
Redis-backed limiter or custom driver.

## Quick start

1) Set a rate limit on the task options:

```dart
TaskOptions(
  queue: 'throttled',
  rateLimit: '3/s',
)
```

2) Wire a rate limiter into the worker:

```dart
final rateLimiter = await connectRateLimiter(config);

final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  rateLimiter: rateLimiter,
);
```

3) Run the `rate_limit_delay` example for a full demo:

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

- `packages/stem/example/rate_limit_delay/lib/rate_limiter.dart`

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

## Tips

- Use shared Redis for global limits across worker processes.
- Keep the rate limit key stable (by default it uses task name + tenant).
- Start with generous limits, then tighten after observing throughput.

## Next steps

- See [Tasks & Retries](./tasks.md) for other `TaskOptions` knobs.
- Use [Observability](./observability.md) to instrument rate-limited flows.
