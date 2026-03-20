---
title: Canvas Patterns
sidebar_label: Canvas
sidebar_position: 5
slug: /core-concepts/canvas
---

This guide walks through Stem's task composition primitives—chains, groups, and
chords—using in-memory brokers and backends. Each snippet references a runnable
file under `packages/stem/example/docs_snippets/` so you can experiment locally
with `dart run`. If you bootstrap with `StemApp`, use `app.canvas` to reuse the
same broker, backend, task handlers, and encoder registry. `StemApp` lazy-starts
its managed worker for canvas dispatch too, so the common path does not need an
explicit `await app.start()`.

## Chains

Chains execute tasks serially. Each step receives the previous result via
`context.meta['chainPrevResult']`.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/canvas_chain.dart#canvas-chain

```

If any step fails, the chain stops immediately. Retry by invoking `canvas.chain`
again with the same signatures.

## Groups

Groups fan out work and persist each branch in the result backend.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/canvas_group.dart#canvas-group

```

## Batches

Batches provide a first-class immutable submission API on top of durable group
state:

- `canvas.submitBatch(signatures)` returns a stable `batchId` and task ids.
- `canvas.inspectBatch(batchId)` returns aggregate lifecycle status
  (`pending`, `running`, `succeeded`, `failed`, `cancelled`, `partial`).

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/canvas_batch.dart#canvas-batch

```

## Chords

Chords combine a group with a callback. Once all body tasks succeed, the callback
runs with `context.meta['chordResults']` populated.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/canvas_chord.dart#canvas-chord

```

If any branch fails, the callback is skipped and the chord group is marked as
failed. Inspect the latest group status via `StemApp.getGroupStatus(...)` or
`StemClient.getGroupStatus(...)` before retrying. If you are operating below
the runtime layer, read the raw backend directly.

## Dependency semantics

- **Chains** model parent → child dependencies: each step is enqueued only after
  the previous one succeeds.
- **Groups** model fan-out dependencies: a group is “complete” once all child
  tasks finish. The expected count is stored in the backend.
- **Chords** combine both: a callback depends on the entire group finishing
  successfully.

## Child result retrieval

- `Canvas.group` returns a `GroupDispatch` with a result stream for each child.
- `Canvas.chord` preserves the original signature order when building
  `chordResults`, so you can map results back to inputs deterministically.
- `StemApp.getGroupStatus(...)` and `StemClient.getGroupStatus(...)` return the
  latest status for each child task. Low-level integrations can still read the
  raw backend directly.

## Removal semantics

Group and chord metadata live in the result backend. Set backend TTLs or
explicitly expire group records to avoid unbounded storage growth.

## Running the examples

From the repository root:

```bash
cd packages/stem/example/docs_snippets
dart run lib/canvas_chain.dart
dart run lib/canvas_group.dart
dart run lib/canvas_chord.dart
```

Each script bootstraps a `StemApp` in-memory runtime and then uses `app.canvas`
for composition.

## Best practices

- Keep callbacks idempotent; chords can be retried manually.
- Polling is fine for examples—production deployments should rely on
  notifications or shorter intervals.
- Expire group records via backend TTLs to avoid unbounded storage.
