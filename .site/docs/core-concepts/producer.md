---
title: Producer API
sidebar_label: Producer API
sidebar_position: 2
slug: /core-concepts/producer
---

Enqueue tasks from your Dart services using `Stem.enqueue`. Start with the
in-memory broker, then opt into Redis/Postgres as needed.

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Enqueue tasks

<Tabs>
<TabItem value="in-memory" label="In-memory (bin/producer.dart)">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/producer.dart#producer-in-memory

```

</TabItem>
<TabItem value="redis" label="Redis + Result Backend (bin/producer_redis.dart)">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/producer.dart#producer-redis

```

</TabItem>
<TabItem value="signed" label="Signed Payloads (bin/producer_signed.dart)">

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/producer.dart#producer-signed

```

</TabItem>
</Tabs>

## Typed Enqueue Helpers

When you need compile-time guarantees for task arguments and result types, wrap
your handler in a `TaskDefinition`. The definition knows how to encode args and
decode results, and exposes a fluent builder for overrides (headers, meta,
options, scheduling):

```dart title="bin/producer_typed.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/producer.dart#producer-typed

```

Typed helpers are also available on `Canvas` (`definition.toSignature`) so
group/chain/chord APIs produce strongly typed `TaskResult<T>` streams.
Need to tweak headers/meta/queue at call sites? Wrap the definition in a
`TaskEnqueueBuilder` and invoke `await builder.enqueueWith(stem);`.

## Enqueue options

Use `TaskEnqueueOptions` to override scheduling, routing, retry behavior, and
callbacks for a single publish. Common fields include `countdown`, `eta`,
`expires`, `queue`, `exchange`, `routingKey`, `priority`, `serializer`,
`compression`, `ignoreResult`, `taskId`, `retry`, `retryPolicy`, `link`, and
`linkError`.

Adapter support varies; for example, not every broker honors priorities or
delayed delivery. Stem falls back to best-effort behavior when a capability is
unsupported.

Example:

```dart
await stem.enqueue(
  'tasks.email',
  args: {'to': 'ops@example.com'},
  enqueueOptions: TaskEnqueueOptions(
    countdown: const Duration(seconds: 30),
    queue: 'critical',
    retry: true,
    retryPolicy: TaskRetryPolicy(
      backoff: true,
      defaultDelay: const Duration(seconds: 2),
      maxRetries: 5,
    ),
  ),
);
```

## Tips

- Reuse a single `Stem` instance; create it during application bootstrap.
- Capture the returned task id when you need to poll status from the result backend.
- Use `TaskOptions` to set queue, retries, priority, isolation, and visibility timeouts.
- `meta` is stored with result backend entries—great for audit trails.
- `headers` travel with the envelope and can carry tracing information.
- To schedule tasks in the future, set `notBefore`.
- For signing configuration, see [Payload Signing](./signing.md).

## Configuring Payload Encoders

Every `Stem`, `StemApp`, `StemWorkflowApp`, and `Canvas` now accepts a
`TaskPayloadEncoderRegistry` or explicit `argsEncoder`/`resultEncoder` values.
Encoders run exactly once in each direction: producers encode arguments, workers
decode them before invoking handlers, and handler return values are encoded
before hitting the result backend. Example:

```dart title="lib/bootstrap_typed_encoders.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/producer.dart#producer-encoders

```

Handlers needing different encoders can override `TaskMetadata.argsEncoder` and
`TaskMetadata.resultEncoder`. The worker automatically stamps every task status
with the encoder id (`__stemResultEncoder`), so downstream consumers and
adapters always know how to decode stored payloads.

Continue with the [Worker guide](../workers/programmatic-integration.md) to
consume the tasks you enqueue.
