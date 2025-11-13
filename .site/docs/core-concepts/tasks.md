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

```dart
import 'package:stem/stem.dart';

class EmailTask implements TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(maxRetries: 2);

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final to = args['to'] as String? ?? 'anonymous';
    print('Emailing $to (attempt ${context.attempt})');
  }
}

final registry = SimpleTaskRegistry()..register(EmailTask());
```

</TabItem>
<TabItem value="redis" label="Redis (tasks/email_task.dart)">

```dart
import 'package:stem/stem.dart';

class EmailTask implements TaskHandler<void> {
  @override
  String get name => 'email.send';

  @override
  TaskOptions get options => const TaskOptions(
        queue: 'email',
        maxRetries: 4,
        visibilityTimeout: Duration(seconds: 30),
        unique: true,
        uniqueFor: Duration(minutes: 5),
      );

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    await sendEmailRemote(args);
  }
}

final registry = SimpleTaskRegistry()..register(EmailTask());
```

</TabItem>
</Tabs>

## Typed Task Definitions

Stem ships with `TaskDefinition<TArgs, TResult>` so producers get compile-time
checks for required arguments and result types. A definition bundles the task
name, argument encoder, optional metadata, and default `TaskOptions`. Build a
call with `.call(args)` or `TaskEnqueueBuilder` and hand it to `Stem.enqueueCall`
or `Canvas` helpers:

```dart
import 'package:stem/stem.dart';

class InvoicePayload {
  const InvoicePayload({required this.invoiceId});
  final String invoiceId;
}

class PublishInvoiceTask implements TaskHandler<void> {
  static final definition = TaskDefinition<InvoicePayload, bool>(
    name: 'invoice.publish',
    encodeArgs: (payload) => {'invoiceId': payload.invoiceId},
    metadata: const TaskMetadata(description: 'Publishes invoices downstream'),
    defaultOptions: const TaskOptions(queue: 'billing'),
  );

  @override
  String get name => definition.name;

  @override
  TaskOptions get options => definition.defaultOptions;

  @override
  Future<void> call(TaskContext context, Map<String, Object?> args) async {
    final invoiceId = args['invoiceId'] as String;
    await publishInvoice(invoiceId);
  }
}

final stem = Stem(
  broker: InMemoryBroker(),
  registry: SimpleTaskRegistry()..register(PublishInvoiceTask()),
  backend: InMemoryResultBackend(),
);

final taskId = await stem.enqueueCall(
  PublishInvoiceTask.definition(const InvoicePayload(invoiceId: 'inv_42')),
);
final result = await stem.waitForTask<bool>(taskId);
if (result?.isSucceeded == true) {
  print('Invoice published');
}
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

```dart
const TaskOptions(
  softTimeLimit: Duration(seconds: 15),
  hardTimeLimit: Duration(seconds: 30),
  acksLate: true,
  isolateEntrypoint: sendEmailIsolate,
);
```

- **Soft timeouts** trigger `WorkerEventType.timeout` so you can log or notify.
- **Hard timeouts** raise `TimeoutException` to force retries or failure.
- Provide an `isolateEntrypoint` to run the task in a dedicated isolate when
  enforcing hard limits or dealing with CPU-intensive code.

## Idempotency Checklist

- Make task inputs explicit (`args`, `headers`, `meta`).
- Guard external calls with idempotency keys.
- Store state transitions atomically (e.g. using Postgres or Redis transactions).
- Set `TaskOptions.unique`/`uniqueFor` for naturally unique jobs.

With these practices in place, tasks can be retried safely and composed via
chains, groups, and chords (see [Canvas Patterns](./canvas.md)).

## Task Payload Encoders

Handlers often need to encrypt, compress, or otherwise transform arguments and
results before they leave the process. Stem exposes `TaskPayloadEncoder` so you
can swap out the default JSON pass-through behavior:

```dart title="Encoders/global.dart"
import 'dart:convert';
import 'package:stem/stem.dart';

class Base64PayloadEncoder extends TaskPayloadEncoder {
  const Base64PayloadEncoder();

  @override
  Object? encode(Object? value) =>
      value is String ? base64Encode(utf8.encode(value)) : value;

  @override
  Object? decode(Object? stored) =>
      stored is String ? utf8.decode(base64Decode(stored)) : stored;
}

final app = await StemApp.inMemory(
  tasks: [...],
  argsEncoder: const Base64PayloadEncoder(),
  resultEncoder: const Base64PayloadEncoder(),
  additionalEncoders: const [MyOtherEncoder()],
);
```

Workers automatically decode arguments once (`stem-args-encoder` header /
`__stemArgsEncoder` meta) and encode results once (`__stemResultEncoder` meta)
before writing to the backend. When you need task-specific behavior, set the
metadata overrides:

```dart
@override
TaskMetadata get metadata => const TaskMetadata(
      argsEncoder: Base64PayloadEncoder(),
      resultEncoder: Base64PayloadEncoder(),
    );
```

Because encoders are centrally registered inside the
`TaskPayloadEncoderRegistry`, every producer/worker instance that shares the
registry can resolve encoder ids reliably—even across processes or languages.
