---
title: Tasks & Retries
sidebar_label: Tasks
sidebar_position: 1
slug: /core-concepts/tasks
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Tasks are the units of work executed by Stem workers. Each task is represented by
a handler registered in a `TaskRegistry`. Handlers expose metadata through
`TaskOptions`, which control routing, retry behavior, timeouts, and isolation.

## Registering Handlers

<Tabs>
<TabItem value="in-memory" label="In-memory (tasks/email_task.dart)">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-register-in-memory

```

</TabItem>
<TabItem value="redis" label="Redis (tasks/email_task.dart)">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-register-redis

```

</TabItem>
</Tabs>

## Typed Task Definitions

Stem ships with `TaskDefinition<TArgs, TResult>` so producers get compile-time
checks for required arguments and result types. A definition bundles the task
name, argument encoder, optional metadata, and default `TaskOptions`. Build a
call with `.call(args)` or `TaskEnqueueBuilder` and hand it to `Stem.enqueueCall`
or `Canvas` helpers:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-typed-definition

```

Typed results flow through `TaskResult<TResult>` when you call
`Stem.waitForTask<TResult>`, `Canvas.group<T>`, `Canvas.chain<T>`, or
`Canvas.chord<T>`. Supplying a custom `decode` callback on the task signature
lets you deserialize complex objects before they reach application code.

## Configuring Retries

Workers apply an `ExponentialJitterRetryStrategy` by default. Each retry is
scheduled by publishing a new envelope with an updated `notBefore`. Control
retry cadence by:

- Setting `TaskOptions.maxRetries` (initial attempt + `maxRetries`).
- Supplying a custom `RetryStrategy` to the worker.
- Tuning the broker connection (e.g. Redis `blockTime`, `claimInterval`,
  `defaultVisibilityTimeout`) so delayed messages are drained quickly.

See the `examples/retry_task` Compose demo for a runnable setup that prints
every retry signal and shows how the strategy interacts with broker timings.

## Task Context

`TaskContext` provides metadata and control helpers:

- `context.attempt` – current attempt number (0-based).
- `context.heartbeat()` – extend the lease to avoid timeouts.
- `context.extendLease(Duration by)` – request additional processing time.
- `context.progress(percent, data: {...})` – emit progress signals for UI hooks.

Use the context to build idempotent handlers. Re-enqueue work, cancel jobs, or
store audit details in `context.meta`.

## Isolation & Timeouts

Set soft/hard timeouts to guard against runaway tasks:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-timeouts

```

- **Soft timeouts** trigger `WorkerEventType.timeout` so you can log or notify.
- **Hard timeouts** raise `TimeoutException` to force retries or failure.
- Provide an `isolateEntrypoint` to run the task in a dedicated isolate when
  enforcing hard limits or dealing with CPU-intensive code.

## Idempotency Checklist

- Make task inputs explicit (`args`, `headers`, `meta`).
- Guard external calls with idempotency keys.
- Store state transitions atomically (e.g. using Postgres or Redis transactions).
- Set `TaskOptions.unique`/`uniqueFor` for naturally unique jobs (see
  [Uniqueness](./uniqueness.md)).
- Use `TaskOptions.rateLimit` with a worker `RateLimiter` to throttle hot tasks
  (see [Rate Limiting](./rate-limiting.md)).

With these practices in place, tasks can be retried safely and composed via
chains, groups, and chords (see [Canvas Patterns](./canvas.md)).

## Task Payload Encoders

Handlers often need to encrypt, compress, or otherwise transform arguments and
results before they leave the process. Stem exposes `TaskPayloadEncoder` so you
can swap out the default JSON pass-through behavior:

```dart title="Encoders/global.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-encoders-global

```

Workers automatically decode arguments once (`stem-args-encoder` header /
`__stemArgsEncoder` meta) and encode results once (`__stemResultEncoder` meta)
before writing to the backend. When you need task-specific behavior, set the
metadata overrides:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-encoders-metadata

```

Because encoders are centrally registered inside the
`TaskPayloadEncoderRegistry`, every producer/worker instance that shares the
registry can resolve encoder ids reliably—even across processes or languages.
