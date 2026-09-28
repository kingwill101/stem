# Durable script concurrency

Script workflows support both concurrent named steps and explicit named
branches. They use the same per-invocation persistence model; handlers are not
silently serialized.

## Concurrent steps

Use ordinary Dart futures when all checkpoints belong to the same scope:

```dart
final results = await Future.wait([
  script.step('customer', (step) => loadCustomer(step.params)),
  script.step('inventory', (step) => loadInventory(step.params)),
]);
```

Each distinct checkpoint has its own result, suspension, deadline, and delivered
event payload. Completing one sibling does not complete another. A sleeping
checkpoint does not restart its timer merely because a sibling event wakes the
workflow.

Names identify logical checkpoints. Two overlapping calls with the same name
and iteration are conflicting invocations, not two independent actions. Use
different names, isolated branches, or `autoVersion: true`. Auto-versioned
iterations are allocated when calls are made, independently of completion order.

## Named branches

Use `parallel` when a branch contains multiple checkpoints or local names should
be reusable:

```dart
final results = await script.parallel<String>({
  'customer': (branch) async {
    final customer = await branch.step('load', (_) => loadCustomer());
    return branch.step('summarize', (_) => summarize(customer));
  },
  'inventory': (branch) async {
    final inventory = await branch.step('load', (_) => loadInventory());
    return branch.step('summarize', (_) => summarize(inventory));
  },
});
```

`customer/load` and `inventory/load` are independent logical checkpoints.
Branches receive their own previous-result state and invocation ordinals.
Nested groups and repeated groups also have separate scopes. The returned map
preserves the supplied branch names. Branch completion does not implicitly
replace the parent scope's previous result; use the returned map for joins.

Branch functions are started even if an earlier branch throws synchronously.
The explicit `parallel` join waits for every branch and prefers an uncaught
branch failure over a sibling's suspension. Multiple failures use declaration
order; loss of execution ownership takes precedence over application errors.
Exceptions caught inside a branch remain handled.

Raw futures retain normal Dart semantics. `Future.wait` exposes its first error,
which may be a suspension before a later sibling error. Use `parallel` when
failure-over-suspension aggregation is required. An exception already caught by
workflow code is not raised again merely because a later checkpoint suspends.
`Future.wait(..., eagerError: true)` may return early to script code, but the
runtime still drains admitted checkpoint work before leaving that execution.

## Identity, ordering, and replay

These are separate concepts:

- `StepInvocationId` encodes branch scope, local checkpoint name, and iteration
  without delimiter ambiguity. It is stable across replay, not a fresh ordered
  UUID generated each time the script executes.
- `stepIndex` is a zero-based invocation ordinal in the current scope. It is
  neither a persistence key nor a completion-order guarantee.
- `previousResult` is captured when a checkpoint is invoked. It does not change
  while that handler awaits. Within a scope, completed results advance this
  state by invocation order, not by whichever sibling happens to finish last.

Keep names, branching decisions, group order, loop order, codecs, and input
schemas compatible with persisted runs. Prefer explicit returned values to
`previousResult` for dependencies between concurrent operations.

The workflow body and branch functions run again after a durable suspension.
Completed checkpoints—including completed null values—replay without running
their handlers. Still-suspended checkpoints do not run just because another
checkpoint becomes ready. Only the matching ready checkpoint receives its
persisted payload or event-timeout indication.

Do not place one-shot in-memory barriers inside handlers that may be skipped
during replay. Durable coordination belongs in checkpoint results, events, or
workflow joins.

## Storage and upgrade behavior

Built-in memory, SQLite, PostgreSQL, and Redis stores implement
`WorkflowConcurrentStore` alongside execution fencing. A durable record carries
its logical ID, execution token, revision, status, encoded result, and independent
suspension metadata. Compare-and-set writes reject stale revisions and execution
claims. Event and timer delivery preserve all siblings' buffered payloads.
Ordinary checkpoint views are written in the same transaction as successful
per-invocation records, avoiding a separate unfenced compatibility write.

The parent run's single `resumeAt`, `waitTopic`, and `suspensionData` fields are
an operator-facing projection, not the authoritative state of every branch.
While the execution lease is active, a suspended child does not release it.
Lease release projects remaining child states onto the parent. Resolving a child
makes the parent runnable without invalidating an active sibling's claim.
`releaseConcurrentExecution` settles the observed script outcome and releases
the claim atomically. On suspension, failed checkpoint records remain available
for diagnostics and replay but do not force the parent into a retry loop.
An escaping script failure instead leaves an active run runnable for retry.

SQLite and PostgreSQL add a concurrent-checkpoint table through their migration
registries. Redis uses separate per-run records and topic/timer indexes. Existing
sequential checkpoints and resume metadata remain readable.

Upgrade all workers that can execute the affected workflows before submitting
concurrent runs. Old workers do not understand per-invocation wait state; do not
mix old and new runtimes on these runs or downgrade while they remain in flight.

Custom stores without the concurrent capability retain sequential execution.
Overlapping calls and `parallel` fail clearly instead of silently using the old
singleton suspension model.

## Boundaries

- Events are delivered to registered durable watchers. This is not an event
  inbox for messages emitted before registration.
- Checkpoint side effects must still be idempotent. Persistence and external
  services are not one transaction; a process crash can repeat uncommitted work.
- Dart futures do not provide cancellation of arbitrary handler code. Draining
  siblings is not forcibly interrupting their external operations.
- A checkpoint has one durable suspension at a time. Put multiple successive
  waits in separate checkpoints.
- Routing and timing fields in suspension `data` are runtime-owned. User data
  cannot override checkpoint identity, topics, deadlines, or resume reasons.
  Put arbitrary data with those names inside `payload` or another nested field.
- Caller-managed futures that have not yet invoked a checkpoint are not visible
  to the runtime. Await them in the workflow body, or use a structured branch.

## Regression coverage

`runWorkflowConcurrencyContractTests` runs the same public-runtime scenarios
against every built-in store. It covers independent event delivery and timers,
runtime recreation, simultaneous payload delivery, timeout metadata, null
results, scoped local names, eager failures, batch wakeups, filtering before
limits, caught errors, explicit join outcomes, and revision conflicts. The
original shared-state reproductions now
assert independent indices, stable result snapshots, and preserved deadlines.
