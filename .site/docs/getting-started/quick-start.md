---
title: Quick Start
sidebar_label: Quick Start
sidebar_position: 2
slug: /getting-started/quick-start
---

This is the shortest hosted-workflow example. It uses only memory, so it is
safe to run locally but deliberately does not survive a process restart.

This example targets the current source API and requires a Stem version that
includes `WorkflowHost`. `dart pub add stem` resolves a published release, which
may not include this API yet. Check that release's documentation first. To
try the current source before publication, replace the `stem` dependency with
a path dependency on your checkout:

```yaml
dependencies:
  stem:
    path: /absolute/path/to/stem/packages/stem
```

Run `dart pub get` after changing the dependency. Use a Dart 3.13+ SDK for the
current source.

```bash
dart create hosted_demo
cd hosted_demo
dart pub add stem
```

Replace `bin/hosted_demo.dart` with:

```dart
import 'package:stem/stem.dart';

final greeting = HostedWorkflow<String, String>(
  name: 'greeting',
  run: (context, name) async {
    final cleaned = await context.step('normalize-name', () => name.trim());
    await context.sleep('small-pause', const Duration(milliseconds: 10));
    return cleaned.isEmpty ? 'Hello, stranger!' : 'Hello, $cleaned!';
  },
);

Future<void> main() async {
  final host = await WorkflowHost.inMemory(workflows: [greeting]);
  try {
    final run = await host.submit(greeting, ' Ada ');
    print('${run.id}: ${await run.result}'); // Hello, Ada!
  } finally {
    await host.close();
  }
}
```

Run it:

```bash
dart run
```

`submit` persists and enqueues a run, returning a typed `HostedRun`. Accessing
`result` observes the terminal result. A timeout on result observation (if you
configure `resultTimeout`) does **not** cancel execution; call `observe` with
the saved ID to watch again. `cancel()` is an explicit durable cancellation
request and does not roll back an external side effect already performed.

## Important boundaries

The in-memory broker, backend, and workflow store are process-local. They are
excellent for a demo and tests, but nothing can be recovered after a restart.
For restart durability, follow [Choosing a backend](./choosing-a-backend.md)
and create the host through an app factory.

Each `context.step` callback executes in the local worker process. It is not a
remote activity, and `host.close()` is not cancellation: owned app shutdown
waits for admitted operations and may drain an active handler.

## Continue

- Add independent queued work with [First Steps](./first-steps.md).
- Learn the full workflow lifecycle in
  [Workflow getting started](../workflows/getting-started.md).
- For persistence and restart recovery, read
  [Next Steps](./next-steps.md).
