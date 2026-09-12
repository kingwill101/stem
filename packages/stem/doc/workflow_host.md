# Typed workflow hosts

`WorkflowHost` is an application-facing facade over `StemWorkflowApp` and its
existing script runtime. It does not create another workflow engine.

See the runnable [greeting example](../example/workflows/hosted.dart).

```dart
final greeting = HostedWorkflow<String, String>(
  name: 'greeting',
  run: (context, name) async {
    final cleaned = await context.step('normalize', () => name.trim());
    await context.sleep('pause', const Duration(seconds: 1));
    return 'Hello, $cleaned!';
  },
);

final host = await WorkflowHost.inMemory(workflows: [greeting]);
try {
  final run = await host.submit(greeting, ' Ada ');
  print(await run.result);
} finally {
  await host.close();
}
```

## Ownership and shutdown

- `WorkflowHost.inMemory` creates, starts, and owns an in-memory app.
- `WorkflowHost.create` passes bound definitions to an application factory,
  starts the returned app, and owns its cleanup. The factory must register
  those definitions unchanged. If the factory fails before returning, cleanup
  is the factory's responsibility.
- `WorkflowHost.attach` borrows an app: it neither starts nor closes it.
  The caller must register equivalent hosted definitions and codecs first.
  Definition IDs can be checked; arbitrary Dart bodies and codec semantics
  cannot be compared through a manifest.

`close()` is idempotent. It rejects new operations, ends local observations,
joins already admitted submissions/reads/event emissions/cancellation calls,
then closes the owned app. It does not delete or cancel persisted workflow
runs. App shutdown may need to drain an active handler; the host does not
forcibly interrupt Dart code.

Joining admitted writes can outlast an observation deadline. A timeout is not
cancellation of the underlying database operation.

## Typed handles and observation

`submit(definition, input)` returns a `HostedRun<R>`:

- `id`: retain this identifier for reattachment.
- `result`: lazily starts result observation and caches that handle's outcome.
- `status()`: reads a current `WorkflowRunView`.
- `watch()`: streams snapshots from shared, bounded-frequency store polling.
- `cancel()`: requests durable cancellation through the existing runtime.

Hosted cancellation requires `WorkflowTerminalStore`. Bundled stores implement
its atomic first-terminal-transition-wins rule: cancellation cannot replace a
completed/failed run, and late completion cannot replace cancellation. A
rejected transition emits no completion/cancellation notification. Ordinary
resume and suspension writes cannot resurrect a terminal run; explicit
administrative rewind remains a separate operation. This does not forcibly
stop an executing Dart body or roll back its external side effects.

`execute(definition, input)` is shorthand for submission followed by result
observation. Use a new handle from `observe` to observe again after a timeout.

`resultTimeout` starts on first access to a handle's result. Expiry throws
`TimeoutException` without cancelling the workflow. Failure or cancellation
throws `HostedWorkflowFailure`. Closing the host stops outstanding result
observation with `StateError`.

Snapshot streams are **not lifecycle-event history**: short intermediate states
may be missed. Concurrent subscriptions for a run share a polling loop; paused
subscriptions may skip intermediate snapshots. Cancelling the last subscriber
or closing the host cancels its poll timer. The default interval is 100 ms.

## Serialization

Inputs, results, and checkpoint values use standard `Codec<T, Object?>`.
Built-in registry defaults cover supported JSON-compatible scalars and broad
JSON containers. DTOs and more specific collection shapes need an explicit
codec, supplied on the definition/checkpoint or registered once in
`PayloadCodecRegistry`.

The host snapshots registrations before creating resources. An equivalent
same-name definition may be passed to `submit` or `observe`, but its generic
input/result types must match and the host's registered codecs/body remain
authoritative. No reflection or automatic `fromJson` discovery is performed.

Inputs are stored in an `input` envelope; checkpoint values use a `value`
envelope, including null. Final results use a tagged, versioned host envelope,
so the configured result codec encodes every result, including null values
represented by a non-null sentinel. `HostedRun.result` unwraps and decodes;
raw store/status results expose the wire envelope. The low-level `bind` method
therefore produces a map-result definition, not the domain result type.

This unreleased host format does not decode unwrapped results from earlier
development drafts. Use fresh test runs or explicitly migrate those draft
records; the host does not guess a format from arbitrary user payload maps.
Custom binary codecs must still produce a backend-compatible representation.

## Durable waits

`context.sleep(name, duration)` uses a named script checkpoint and existing
durable wake-up scheduling.

`context.awaitEvent(name, event, deadline: ...)` registers an existing workflow
event watcher. Send through `host.emitEvent(event, value)`. The event codec—or
host registry codec—must encode to a string-keyed map. The map can decode into
a nullable DTO; raw null is not a transport payload.

Events are topic-scoped and may resume multiple matching runs. They are not
run-addressed messages, and this API does not add buffering for events sent
before watchers are registered. Design topic names and delivery ordering
accordingly.

An event deadline throws `TimeoutException`, based on trusted runtime resume
metadata rather than fields in the user event payload. A caught timeout is
checkpointed and replays as a timeout. An uncaught timeout follows the existing
workflow task-failure policy; the host adds no separate retry loop.

## Persistent restart

Configure adapters through the existing app factory, keeping adapter
dependencies out of core:

```dart
final host = await WorkflowHost.create(
  workflows: [greeting],
  createApp: (definitions) => StemWorkflowApp.fromUrl(
    'sqlite:///path/to/workflows.sqlite',
    adapters: const [StemSqliteAdapter()],
    workflows: definitions,
  ),
);
```

This snippet also requires `package:stem_sqlite/stem_sqlite.dart`.
After closing and reopening with the same durable storage, re-register
executable definitions and use:

```dart
final run = await host.observe(greeting, savedRunId);
final current = await run.status();
```

Reattachment reads the stored run; it does not submit another execution.
Completed checkpoints replay from storage and completed runs return their
stored result. Closures are not serialized: keep definition names, checkpoint
names/order, input schema, and codecs compatible with in-flight runs.
The host does not implement automatic fingerprint migration or reject all
incompatible code changes on startup.

## Scope

This milestone does not add compensation, new durable per-step retry policies,
queued-task-result suspension, or Flutter lifecycle bindings. Use idempotency
for external effects: checkpointing is not an exactly-once side-effect guarantee.
Runtime lease/failure fencing remains subject to the selected store's
capabilities.
