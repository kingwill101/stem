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
