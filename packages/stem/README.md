# Stem

[![pub package](https://img.shields.io/pub/v/stem.svg)](https://pub.dev/packages/stem)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.13-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

Stem is an experimental Dart-first library for background tasks and durable
workflows. It provides task definitions, workers, queues, retries, scheduling,
workflow state, and pluggable broker/result-store adapters.

## Choose your starting point

- **A generated task** is the best default for application code. Annotate a
  typed function or workflow with `stem_builder`, run the generator, and use
  the generated definitions. See the [builder examples](example/annotated_workflows/).
- **`WorkflowHost`** is for typed workflow submission, results, status,
  cancellation, durable sleeps, and event waits. Start with the
  [typed workflow host guide](doc/workflow_host.md) and its
  [runnable hosted example](example/workflows/hosted.dart).
- **A manual `TaskDefinition<TArgs, TResult>`** is a typed task without code generation.
  The map-based APIs in `package:stem/advanced.dart` are for custom
  transports and migrations, not the usual first application.

## Install

```bash
dart pub add stem
# Optional code generation:
dart pub add --dev stem_builder build_runner
```

The current package requires **Dart SDK 3.13 or newer**
(`>=3.13.0 <4.0.0`). This floor is part of the current source package; choose a
released package version whose SDK constraint matches your application if you
use an older SDK.

Repository examples describe this source version, which can be ahead of pub.dev.
Use the documentation for your resolved release when an API shown here is not
available in your installed package.

Application code can import `package:stem/stable.dart`. The historical
`package:stem/stem.dart` barrel remains available for compatibility. For
in-memory implementations, use `package:stem/memory.dart`.

## A complete typed task

This runnable in-memory example is deterministic: `enqueueAndWait` waits for
the worker result rather than guessing with `Future.delayed`. The `finally`
block closes resources when the handler fails too.

```dart
import 'dart:async';

import 'package:stem/stable.dart';

class GreetingArgs {
  const GreetingArgs({required this.name});

  final String name;

  Map<String, dynamic> toJson() => {'name': name};

  factory GreetingArgs.fromJson(Map<String, dynamic> json) =>
      GreetingArgs(name: json['name'] as String);
}

final greetingDefinition = TaskDefinition<GreetingArgs, String>.json(
  name: 'demo.greeting',
  decodeArgsJson: GreetingArgs.fromJson,
);

final greetingTask = greetingDefinition.handler(
  entrypoint: (context, args) async => 'Hello, ${args.name}!',
);

Future<void> main() async {
  final client = await StemClient.inMemory(tasks: [greetingTask]);
  final worker = await client.createWorker();
  unawaited(worker.start());

  try {
    final result = await greetingDefinition.enqueueAndWait(
      client,
      const GreetingArgs(name: 'Stem'),
    );
    print(result?.value); // Hello, Stem!
  } finally {
    await worker.shutdown();
    await client.close();
  }
}
```

For a map-based first-steps example, see
[`first_steps.dart`](example/docs_snippets/lib/first_steps.dart). For
annotations and generated definitions, see the
[`stem_builder` package](https://pub.dev/packages/stem_builder) and run:

```bash
dart run build_runner build
```

## Typed workflows

Use `WorkflowHost.inMemory` when the host should create, start, and own the
workflow application. The following is a fragment for an async function with
`package:stem/stem.dart` imported; see the linked example for a complete program:

```dart
final greeting = HostedWorkflow<String, String>(
  name: 'greeting',
  run: (context, name) async => 'Hello, ${name.trim()}!',
);

final host = await WorkflowHost.inMemory(workflows: [greeting]);
try {
  final run = await host.submit(greeting, ' Ada ');
  print(await run.result); // Hello, Ada!
} finally {
  await host.close();
}
```

The [workflow host guide](doc/workflow_host.md) covers durable checkpoints and
sleeps, event waits, typed codecs, persistent restart, observation versus
cancellation, and adapter configuration. Reattaching with `host.observe`
observes an existing run; it does not submit a second execution.

## Adapters and deployment shape

The core package includes in-memory adapters for local development and tests.
For durable or shared storage, choose an adapter package and configure it
through the relevant `StemApp`/`StemWorkflowApp` factory:

- [`stem_redis`](https://pub.dev/packages/stem_redis) — Redis Streams broker,
  result backend, and workflow store.
- [`stem_postgres`](https://pub.dev/packages/stem_postgres) — Postgres broker, result backend, and
  scheduler stores.
- [`stem_sqlite`](https://pub.dev/packages/stem_sqlite) — SQLite queue, results,
  and workflow storage for local persistence.

Adapter packages own their connection settings and operational requirements.
Read their package README and the
[adapter guide](https://kingwill101.github.io/stem/) before selecting one.
Core does not promise identical delivery, change-feed, or durability behavior
across adapters. A broker can redeliver work, so task side effects should
tolerate retries and duplicate delivery.

## Capabilities and boundaries

- Tasks support typed definitions, queues, delayed enqueue, priorities,
  idempotency helpers, retries, task results, and worker controls.
- Workflows persist checkpoints and can resume through the configured store.
  `WorkflowHost` adds typed submission and observation; it does not forcibly
  stop executing Dart code or roll back external side effects.
- Scheduling, observability, signing, dashboards, and CLI operations are
  available in surrounding packages and examples, with their own configuration
  and dependencies.
- In-memory storage is process-local and intended for development/tests. It
  cannot provide persistence across process death.
- Delivery is not exactly once. Durable state does not make external effects
  transactional; use application-level idempotency keys and transactions where
  those effects require them.

See the [getting started guide](https://kingwill101.github.io/stem/) and
[all examples](example/) for supported setup paths and complete topologies.

## AI skills

With the official Dart skills tooling, install Stem skills with:

```bash
dart run skills@ get -p stem
```

Only package versions that ship the skills definitions can provide these
skills. The command does not replace Stem documentation or package setup.

## CLI

Install the optional CLI package to use the `stem` executable:

```bash
dart pub add --dev stem_cli
dart run stem_cli:stem --help
dart run stem_cli:stem worker --help
dart run stem_cli:stem wf --help
```

## Interrupted deliveries

Workers recognize a redelivered task whose retained backend status is `running`
for the **same attempt**, after suppressing duplicates already active in that
worker. `StemSignals.onTaskInterrupted` (from `stem.dart` or `advanced.dart`)
receives a typed payload containing the previous status, current envelope,
recovering worker, and selected recovery policy before recovery.

The default `TaskOptions(recoveryPolicy: TaskRecoveryPolicy.replay)` preserves
historical behavior: execute the same attempt again. Opt into
`TaskRecoveryPolicy.retry` to classify a `TaskInterruptedException` through the
normal retry policy: `maxRetries`, backoff, and `autoRetryFor`/
`dontAutoRetryFor` all apply. With no retries available, recovery fails the task
without invoking its handler. The option survives JSON serialization and
`copyWith`.

Interruption is reported before pause or rate-limit deferrals can replace the
running status. Retry recovery classifies the interrupted attempt even if its
queue is paused or rate-limited; it does not execute task code. Any resulting
next attempt still respects those scheduling controls. Default replay continues
to respect them too, and the notification describes detection, not successful
completion of recovery.

This is evidence of potentially interrupted or lease-lost execution, **not**
proof of process death, out-of-memory termination, or any OS kill reason.
Notifications occur on redelivery, not while the application is dead; they are
in-process signals, not a durable notification outbox. They require retained
running status and a broker that redelivers unacknowledged work. An in-memory
backend cannot retain this evidence across process death. A previous worker may
still be executing after lease loss. Neither replay nor retry provides
exactly-once execution or makes non-idempotent side effects safe; use
idempotency keys and transactional application-level safeguards.
