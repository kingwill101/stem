# Typed workflow hosts

`WorkflowHost` is an application-facing facade over `StemWorkflowApp` and its
existing script runtime. It does not create another workflow engine.

See the runnable [greeting example](../example/workflows/hosted.dart).
The [compensation example](../example/workflows/hosted_compensation.dart) shows
exhausted action retries followed by result-aware cleanup.

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
- `watch()`: shares native store changes where complete, otherwise store polling.
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
may be missed. Concurrent subscriptions share one observation source. The
optional `WorkflowRunChanges` capability eliminates idle polling for the
in-memory store. Persistent adapters use polling unless they can provide a
complete cross-process change feed; local ORM hooks are not sufficient.
If a native source fails or closes, the host falls back to polling.

Paused subscriptions may skip intermediate snapshots. Cancelling the last
subscriber or closing the host cancels the source/timer, and host shutdown
joins native-source cleanup before closing owned stores. The default fallback
poll interval is 100 ms.

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

`await host.recover(limit: 100)` re-enqueues one bounded batch of registered
runnable runs, for example after a persisted event resolution lost its
continuation enqueue. Overlapping calls share one scan; a later call starts a
new scan. The report contains enqueued IDs, skipped IDs, and per-run errors.
This is not exactly-once dispatch: an existing delivery may still be present,
and normal execution claims handle duplicates.

Recovery does not force-resume non-due suspensions or bypass live leases.
Existing runtime timer/event handling is still responsible for suspended runs.
The limit bounds candidate scanning, not a promise to recover every run in one
call. Unregistered candidates are skipped and reported, not executed.

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

## Durable action retries

The host is an authoring layer over the existing workflow runtime, not another
execution engine. Ordinary and journaled actions share checkpoint persistence.
The historical `workflow_host_prototype` example now uses this same core host.

Retry configuration remains separate by purpose: task retry policy controls
delivery attempts, a retry strategy computes delivery backoff, and
`WorkflowRetryPolicy` persists a named action's logical budget across deliveries.

Supply `retry` to a named action checkpoint:

```dart
final receipt = await context.step(
  'charge',
  () => paymentClient.charge(orderId),
  retry: const WorkflowRetryPolicy(
    maxAttempts: 3,
    delay: Duration(seconds: 1),
    multiplier: 2,
    maxDelay: Duration(seconds: 10),
  ),
);
```

`maxAttempts` includes the first attempt and abandoned claims after a crash.
The journal persists attempts and absolute retry times; transport redelivery
does not reset the budget. Backoff suspends the workflow through existing
durable scheduling, including zero-delay retries. No local retry loop sleeps
inside an active action.

An exhausted action throws `WorkflowStepRetryExhausted`. If uncaught, this
terminal failure vetoes another automatic task-level retry. Other task errors
retain their existing retry policy. Put durable sleeps and event waits outside
retrying action bodies. Named action order and retry policies must remain
compatible with persisted attempts.

## Result-aware compensation

Define cleanup as a named typed registration so a fresh process can reconstruct
the handler without serializing closures:

```dart
final undoReservation = HostedCompensation<String>(
  name: 'undo-reservation',
  run: (context, reservationId) => reservations.release(
    reservationId,
    idempotencyKey: context.idempotencyKey,
  ),
  retryPolicy: const WorkflowRetryPolicy(maxAttempts: 3),
);

final order = HostedWorkflow<String, String>(
  name: 'place-order',
  compensations: [undoReservation],
  run: (context, orderId) async {
    final reservationId = await context.step(
      'reserve',
      () => reservations.create(orderId),
      compensation: undoReservation,
    );
    return context.step(
      'charge',
      () => payments.charge(reservationId),
      retry: const WorkflowRetryPolicy(maxAttempts: 3),
    );
  },
);
```

Successful checkpoint persistence and its encoded compensation input snapshot
commit atomically. On exhausted workflow failure, the runtime enqueues cleanup
on the existing workflow worker. Cleanup runs in reverse successful completion
order. Its leases, retry budget, and completed markers are separate journal
records; completed cleanup is not automatically executed again.

The run becomes **failed before cleanup finishes**. Read `run.compensations()`
to inspect progress. Exhausted cleanup stops the reverse-order sequence rather
than silently skipping an operation. An operator can call:

```dart
await run.retryCompensations(additionalAttempts: 1);
```

This extends exhausted budgets without resetting lifetime attempt counts.
Calling it without an extension repairs a missing cleanup delivery for pending
work. An expired cleanup lease can be reclaimed; `context.heartbeat()` is also
available, and the runtime renews active cleanup leases automatically.

Cancellation, host closure, and observation timeout do **not** activate
compensation. Named handlers and codecs must remain registered for in-flight
cleanup after deployment/restart. Administrative rewind invalidates old claims
and discards journal records for removed checkpoints; it does not undo external
effects or restore effects that were already compensated.

## Storage and guarantees

`StemWorkflowApp.resumeDueRuns()` delegates to the runtime's due-run pipeline
and now enqueues continuations by default. Manual execution drivers can call
`app.runtime.resumeDueRuns(now: time, enqueue: false)` and execute the returned
run IDs themselves. Runtime polling uses the same pipeline, including deadline
metadata and cancellation policy checks.

This consolidation does not make resumption and broker publication atomic.
Publication failures can leave runnable runs requiring recovery. PostgreSQL
already provides a transactional outbox for explicitly coordinated application
writes and publication; the host does not automatically wrap every transition
in that outbox.

Journaled actions require both execution fencing and `WorkflowJournalStore`.
The memory, SQLite, PostgreSQL, and Redis stores implement this capability.
SQL deployments need the new workflow-journal migration. Journal records are
separate from ordinary checkpoints and do not affect workflow cursor counts.

Drain or isolate older workflow workers before enabling journaled definitions.
All consumers of their workflow/continuation queues must understand the journal
and compensation task phase; an older consumer can otherwise acknowledge work
without performing the new phase.

Use idempotency for external operations. A crash after an external effect but
before the journal commit can cause another attempt: this remains at-least-once,
not an exactly-once side-effect guarantee. Compensation is an application
operation, not a database transaction spanning external services.

Optional Flutter bindings consume the same core handles/recovery reports.
Queued-task-result suspension and OS background scheduling are not introduced
by this API.
