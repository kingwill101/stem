# Rate Limit & Delayed Delivery Demo

This example exercises Stem’s rate limiting, delayed delivery, and priority
clamping features using Redis. A burst of tasks is enqueued with different
priorities and optional `notBefore` timestamps. A custom Redis-backed rate
limiter enforces a global `3/s` token bucket; denied tasks are rescheduled with
backoff, and priority values are clamped to the queue’s `[1,5]` range.

## Topology

- **Redis** – shared broker, result backend, and rate limiter store.
- **Producer** – enqueues jobs with mixed delays and priority overrides.
- **Worker** – processes the `throttled` queue with a fixed-window rate limiter,
  logging when work is deferred.

## Quick Start (Docker Compose)

```bash
cd examples/rate_limit_delay
docker compose up --build
```

You should see logs similar to:

```
rate-limit-delay-producer-1  | [producer] job=1 priority=9 applied=5 delay=0s id=...
rate-limit-delay-worker-1    | [rate-limiter][granted] key=demo.throttled.render:global tokens=3 window=1000ms -> available immediately
rate-limit-delay-worker-1    | [worker][start] job=1 attempt=0 requestedPriority=9 appliedPriority=5 rateLimited=false ...
rate-limit-delay-worker-1    | [rate-limiter][denied] key=demo.throttled.render:global tokens=3 window=1000ms -> retry in 872ms
rate-limit-delay-worker-1    | [signal][retry] task=demo.throttled.render retry=0 next=...
```

`docker compose down` tears everything down.

## Manual Workflow

1. Start Redis:

   ```bash
   docker run --rm -p 6381:6379 redis:7-alpine
   ```

2. In one terminal, run the worker:

   ```bash
   cd examples/rate_limit_delay
   STEM_BROKER_URL=redis://localhost:6381/0 \
   STEM_RESULT_BACKEND_URL=redis://localhost:6381/1 \
   STEM_RATE_LIMIT_URL=redis://localhost:6381/2 \
   dart run bin/worker.dart
   ```

3. In another terminal, run the producer:

   ```bash
   cd examples/rate_limit_delay
   STEM_BROKER_URL=redis://localhost:6381/0 \
   STEM_RESULT_BACKEND_URL=redis://localhost:6381/1 \
   dart run bin/producer.dart
   ```

## What to Observe

- **Rate limiting:** the custom Redis fixed-window limiter logs whether tokens
  were granted or denied, with `retryAfter` durations surfaced in the worker.
- **Delayed delivery:** half the jobs include a `notBefore` timestamp—watch the
  worker start times versus the scheduled time in the log output.
- **Priority clamping:** tasks request priority 9, but the routing config clamps
  them to 5. The worker logs both requested and applied priorities.
- **Signals:** task lifecycle signals (`taskReceived`, `taskRetry`) are attached
  to show rescheduling when the limiter denies a token.

Inspect the queue and result backend while the demo runs:

```bash
docker compose exec worker \
  stem observe tasks list --broker "$STEM_BROKER_URL" --queue throttled

docker compose exec worker \
  stem observe tasks show --result-backend "$STEM_RESULT_BACKEND_URL" --id <TASK_ID>
```

## Cleanup

```bash
docker compose down
```
