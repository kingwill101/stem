---
title: Tasks & Retries
sidebar_label: Tasks
sidebar_position: 1
slug: /core-concepts/tasks
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Tasks are the units of work executed by Stem workers. In the common path, you
provide handlers directly via `tasks: [...]` on `Stem`, `Worker`, `StemApp`, or
`StemClient`. Handlers expose metadata through `TaskOptions`, which control
routing, retry behavior, timeouts, and isolation.

## Providing Handlers

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
name, argument encoder, optional metadata, and default `TaskOptions`. For the
common path, use the direct
`definition.enqueue(stem, args)` / `definition.enqueueAndWait(...)`
helpers. When you need a reusable prebuilt request, use
`definition.buildCall(args, ...)` and hand the resulting `TaskCall` to any
`TaskResultCaller` / `TaskEnqueuer` surface. Treat `TaskCall` as the
explicit low-level transport object, not the normal happy path:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-typed-definition

```

Typed results flow through `TaskResult<TResult>` when you call
`Stem.waitForTask<TResult>`, `Canvas.group<T>`, `Canvas.chain<T>`, or
`Canvas.chord<T>`. Supplying a custom `decode` callback on the task signature
lets you deserialize complex objects before they reach application code.
Use `result.requiredValue()` when a completed task must have a decoded value
and you want a fail-fast read instead of manual nullable handling.
For low-level DTO waits through `Stem.waitForTask<TResult>`, prefer
`decodeJson:` for plain DTOs or `decodeVersionedJson:` when the stored payload
persists an explicit schema version.
If you already have a raw `TaskStatus`, use `status.payloadJson(...)` or
`status.payloadAs(codec: ...)` to decode the whole payload DTO without a
separate cast/closure. Use `status.payloadVersionedJson(...)` when the stored
payload carries an explicit `__stemPayloadVersion`. If the whole task metadata
map is one DTO, use `status.metaJson(...)` or `status.metaAs(codec: ...)`
instead of manual `status.meta[...]` casts.
If you already have a raw `TaskResult<Object?>`, use `result.payloadJson(...)`
or `result.payloadAs(codec: ...)` to decode the stored task result DTO
without another cast/closure. Use `result.payloadVersionedJson(...)` for the
same versioned DTO path on persisted task results.
If you are inspecting a low-level `TaskError`, use `error.metaJson(...)`,
`error.metaVersionedJson(...)`, or `error.metaAs(codec: ...)` instead of
manual `error.meta[...]` casts.

If your manual task args are DTOs, prefer `TaskDefinition.json(...)`
when the type already has `toJson()`. Use `TaskDefinition.versionedJson(...)`
when the payload schema is expected to evolve and the published payload should
persist an explicit `__stemPayloadVersion`. Use `TaskDefinition.codec(...)`
when you need a custom `PayloadCodec<T>`. Task args still need to encode to a
string-keyed map (typically `Map<String, dynamic>`) because they are published
as JSON-shaped data. For low-level name-based enqueue APIs, use
`enqueueVersionedJson(...)` for the same versioned DTO path.

For manual handlers, prefer the typed payload readers on the argument map
instead of repeating raw casts:

```dart
final customerId = args.requiredValue<String>('customerId');
final tenant = args.valueOr<String>('tenant', 'global');
```

When the whole task arg payload is one DTO, prefer decoding it directly from
the execution context:

```dart
final request = context.argsJson<InvoicePayload>(
  decode: InvoicePayload.fromJson,
);
```

Use `buildCall(...)` when you need an explicit low-level transport object and
provide the final headers, metadata, options, or scheduling overrides up
front. For the normal case, prefer direct `enqueue(...)` /
`enqueueAndWait(...)`.

For tasks with no producer inputs, use `TaskDefinition.noArgs<TResult>(...)`
instead. That gives you direct `enqueue(...)` /
`enqueueAndWait(...)` helpers without passing a fake empty map and the same
`waitFor(...)` decoding surface as normal typed definitions.

If a no-arg task returns a DTO, prefer `TaskDefinition.noArgsJson(...)` when
the result already has `toJson()` and `Type.fromJson(...)`. Use
`TaskDefinition.noArgsCodec(...)` only when you need a custom payload codec.

## Configuring Retries

Workers apply an `ExponentialJitterRetryStrategy` by default. Each retry is
scheduled by publishing a new envelope with an updated `notBefore`. Control
retry cadence by:

- Setting `TaskOptions.maxRetries` (initial attempt + `maxRetries`).
- Supplying a custom `RetryStrategy` to the worker.
- Tuning the broker connection (e.g. Redis `blockTime`, `claimInterval`,
  `defaultVisibilityTimeout`) so delayed messages are drained quickly.

See the `packages/stem/example/retry_task` Compose demo for a runnable setup that prints
every retry signal and shows how the strategy interacts with broker timings.

```dart title="lib/retry_backoff.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/retry_backoff.dart#retry-backoff-strategy

```

```dart title="lib/retry_backoff.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/retry_backoff.dart#retry-backoff-worker

```

## Task Context

`TaskContext` provides metadata and control helpers:

- `context.attempt` – current attempt number (0-based).
- `context.heartbeat()` – extend the lease to avoid timeouts.
- `context.extendLease(Duration by)` – request additional processing time.
- `context.progress(percent, data: {...})` – emit progress signals for UI hooks.
- `context.progressJson(percent, dto)` – emit DTO progress payloads without
  hand-built maps.
- `context.progressVersionedJson(percent, dto, version: n)` – emit DTO progress
  payloads with an explicit persisted schema version.
- `context.retry(...)` – request an immediate retry with optional per-call
  retry policy overrides.
- when you inspect a raw `ProgressSignal`, prefer
  `signal.dataJson('key', ...)`, `signal.dataVersionedJson('key', ...)`, or
  `signal.dataValue<T>('key')` for keyed reads, or
  `signal.payloadJson(...)`, `signal.payloadVersionedJson(...)`, and
  `signal.payloadAs(codec: ...)` when the whole progress payload is one DTO.

Use the context to build idempotent handlers. Re-enqueue work, cancel jobs, or
store audit details in `context.meta`.

For handler inputs, prefer the typed arg helpers on the task context when
available:

```dart
final customerId = context.requiredArg<String>('customerId');
final tenant = context.argOr<String>('tenant', 'global');
```

See the `packages/stem/example/task_context_mixed` demo for a runnable sample that exercises
inline + isolate enqueue, TaskRetryPolicy overrides, and enqueue options.
The `packages/stem/example/task_usage_patterns.dart` sample shows in-memory
`TaskExecutionContext` patterns without external dependencies.

### Enqueue from a running task

Use `TaskExecutionContext.enqueue`/`spawn` to schedule follow-up work with the
same defaults as `Stem.enqueue`. Concrete runtimes like `TaskContext` and
`TaskInvocationContext` expose the same API.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-context-enqueue

```

Inside isolate entrypoints:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/tasks.dart#tasks-invocation-builder

```

When a task runs inside a workflow-enabled runtime like `StemWorkflowApp`,
`TaskExecutionContext` also implements `WorkflowCaller`, so handlers and
isolate entrypoints can start or wait for
typed child workflows without dropping to raw workflow-name APIs. For manual
flows and scripts, prefer `childFlow.startAndWait(context)` or
`childWorkflowRef.startAndWait(context, params: value)` for the simple case.
Use a builder only when you need advanced overrides.

That same shared task context also implements `WorkflowEventEmitter`, so tasks
can resume waiting workflows through `emitValue(...)` or typed `WorkflowEventRef<T>`
instances when a workflow runtime is attached.

### Retry from a running task

Handlers can request a retry directly from the context:

```dart
await context.retry(countdown: const Duration(seconds: 10));
```

Retries respect `TaskOptions.retryPolicy` unless you override it with
`TaskEnqueueOptions.retryPolicy` or `context.retry(retryPolicy: ...)`.

### Retry policy overrides

`TaskRetryPolicy` captures backoff controls and can be applied per handler or
per enqueue:

```dart
final options = TaskOptions(
  maxRetries: 3,
  retryPolicy: TaskRetryPolicy(
    backoff: true,
    defaultDelay: const Duration(seconds: 1),
    backoffMax: const Duration(seconds: 30),
  ),
);
```

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
same encoder configuration can resolve encoder ids reliably, even across
processes or languages.
