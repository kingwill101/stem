---
title: Getting Started
sidebar_position: 1
---

```dart
import 'package:stem/stem.dart';

final workflow = HostedWorkflow<String, String>(
  name: 'welcome',
  run: (context, name) async {
    final cleaned = await context.step('normalize', () => name.trim());
    return 'Welcome, $cleaned!';
  },
);

Future<void> main() async {
  final host = await WorkflowHost.inMemory(workflows: [workflow]);
  try {
    final run = await host.submit(workflow, 'Ada');
    print(await run.result);
  } finally {
    await host.close();
  }
}
```

`inMemory` creates, starts, and owns the app. `submit` persists and enqueues
one run; `result` observes it. Closing neither deletes nor cancels a run.

For production, use `WorkflowHost.create` with a persistent app factory.
After a restart, re-register compatible definitions and reattach with
`host.observe(workflow, savedRunId)`; this does not submit another execution.
`recover(limit: 100)` re-enqueues a bounded batch of runnable runs, and
duplicate delivery remains possible.

`context.sleep(name, duration)` creates a durable timer checkpoint.
`context.awaitEvent(name, event)` waits for a topic event emitted with
`host.emitEvent(...)`. Events are not run-addressed or buffered before a
watcher exists. Task delivery, replay, and external effects are at least once;
use idempotency keys.
