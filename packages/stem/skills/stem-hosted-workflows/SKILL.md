---
name: stem-hosted-workflows
description: >-
  Use when building typed hosted workflows with WorkflowHost, durable
  checkpoints, recovery, typed results, events, or persistent reattachment.
  Preserve workflow names, checkpoint identities, codecs, and replay-safe side
  effects.
---

# Stem hosted workflows

## Rules

- Define a `HostedWorkflow<I, R>` with a stable `name`, typed input/result, and
  a `run` callback. Register the same executable definitions every time a
  persistent host is opened.
- Put side effects inside named `context.step` checkpoints. A workflow body
  may be replayed; code outside a checkpoint must be deterministic and
  replay-safe.
- Use explicit codecs for DTOs or non-JSON representations. The codec used at
  registration must remain compatible with persisted inputs, checkpoint values,
  and results.
- Hosted workflows are a function-first alternative to annotated flows/scripts,
  not generated wrappers. Pass explicit `inputCodec` and `resultCodec`
  for application DTOs; a type's presence in Dart does not make a codec appear
  in the registry.
- `WorkflowHost.create` starts and owns the returned app. `inMemory` is the
  convenient owned test host. `attach` borrows an already-started app and
  never starts or closes it.
- Use `submit` for a `HostedRun<R>` handle, `execute` when only the terminal
  result is needed, and `observe` to reattach to an existing persisted run.
- `recover` re-enqueues a bounded set of runnable runs after reconnect/restart.
  It does not force a non-due durable sleep or event to resume.
- Duplicate delivery is possible across hosts and after lease expiry. Claims
  arbitrate execution, but external effects still need idempotency. Do not
  promise exactly-once execution or exactly-once side effects.
- `close` stops local observation and owned resources; it does not erase or
  cancel durable runs. Request cancellation explicitly through the run handle.

## Example: typed in-memory host

```dart
import 'package:stem/stable.dart';

Future<void> main() async {
  final workflow = HostedWorkflow<String, String>(
    name: 'greeting',
    run: (context, name) async {
      return context.step('format-greeting', () => 'Hello, $name');
    },
  );
  final host = await WorkflowHost.inMemory(workflows: [workflow]);
  try {
    final run = await host.submit(workflow, 'Ada');
    print(await run.result); // Hello, Ada
  } finally {
    await host.close();
  }
}
```

For a restart-safe persistent adapter, create the app with the package's store
and broker factories, then use `WorkflowHost.create` with the same definitions.
The `createApp` callback must register each bound definition unchanged; do not
construct a second definition with a different callback or codec.

## Durable waits and events

Use `await context.sleep('wait-for-window', duration)` for a durable timer and
`host.emitEvent(event, value)` for topic-based resumption. A timer/event is
durable workflow state, not a mobile background execution request. The host
must be reopened and recovered by an application-controlled process.

Use `context.awaitEvent(checkpointName, event)` to register the wait before
emitting. Events are topic-scoped, may resume multiple runs, and are not buffered
for future watchers. Event codecs must encode a string-keyed map.

## Retry and compensation

- Pass `retry: WorkflowRetryPolicy(...)` to `context.step` for a journal-backed
  logical action budget. Persisted attempts and retry ETAs survive replay;
  transport delivery counts do not reset that budget.
- Register named `HostedCompensation<T>` handlers on the workflow and pass
  `compensation:` to a successful step. The checkpoint result is the cleanup
  input; make that result sufficient to identify the external resource.
- Cleanup runs in reverse completion order after terminal failure, not
  cancellation. Cleanup itself is retryable and must be idempotent.
- Inspect `run.compensations()` and use `run.retryCompensations()` deliberately
  to extend an exhausted cleanup budget. Do not reset history or call it on
  every rebuild/replay.
- These operations require a journal-capable store. In-memory support is still
  process-local; choose a persistent adapter for restart durability.

## Validation checklist

1. Keep names and checkpoint names stable across releases.
2. Reopen with equivalent definitions and codecs before calling `observe`.
3. Test replay, lease expiry, cancellation, and bounded `recover` behavior.
4. Keep compensation handlers named and registered on every startup.
