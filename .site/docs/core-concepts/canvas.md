---
title: Canvas Patterns
sidebar_label: Canvas
sidebar_position: 5
slug: /core-concepts/canvas
description: Compose task work with typed chains, groups, batches and chords.
---

This guide walks through Stem's task composition primitives—chains, groups, and
chords—using in-memory brokers and backends. Each snippet references a runnable
file under `packages/stem/example/docs_snippets/` so you can experiment locally
with `dart run`. If you bootstrap with `StemApp`, use `app.canvas` to reuse the
same broker, backend, task handlers, and encoder registry. Start the worker
explicitly in processes that should consume work; constructing a canvas or
inspecting its state never starts execution as a side effect.

## Chains

Chains execute tasks serially. Each step receives the previous result via
`context.meta`, so prefer typed reads like
`context.meta.valueOr<String>('chainPrevResult', 'fallback')` over raw casts.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/canvas_chain.dart#canvas-chain

```

If any step fails, the chain stops immediately. Retry by invoking `canvas.chain`
again with the same signatures.

For heterogeneous transitions, use the typed fluent API. Each `then` accepts a
`TaskDefinition` whose argument type must match the previous result type, and
the final result is decoded into the last task's result type:

```dart
final download = TaskDefinition<DownloadRequest, DownloadResult>.codec(
  name: 'download',
  argsCodec: downloadRequestCodec,
  resultCodec: downloadResultCodec,
);
final resize = TaskDefinition<DownloadResult, ResizeResult>.codec(
  name: 'resize',
  argsCodec: downloadResultCodec,
  resultCodec: resizeResultCodec,
);

final result = await canvas
    .typedChain(download, request)
    .then(resize)
    .run();
```

The compiler rejects a `then` whose argument type does not accept the previous
task's result. The existing homogeneous `Canvas.chain` remains available for
raw signatures and migration compatibility; it transports the previous result
through `chainPrevResult`.

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

Chords combine a group with a callback. By default, once all body tasks
succeed, the callback runs with `context.meta['chordResults']` populated.
Prefer
`context.meta.valueListOr<T>('chordResults', const [])` over manual list casts
when reading those results.

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/canvas_chord.dart#canvas-chord

```

The default `ChordPolicy.allOrFail()` skips the callback when any branch fails.
Use an explicit policy when a callback should receive terminal failures:

```dart
await canvas.chord(
  body: body,
  callback: summarize,
  policy: const ChordPolicy.collectTerminalResults(),
);
```

`ChordPolicy.collectTerminalResults()` waits for every body task and passes
`null` in `chordResults` for failed or cancelled branches. The callback also
receives failure summaries in `context.meta['stem.chord.failures']`.
`ChordPolicy.allowPartial(minSuccessful: 2)` has the same terminal-result
behavior but dispatches only when the required number of body tasks succeeded.
If the policy cannot be satisfied, the callback is skipped and the chord
operation fails. Inspect the latest group status via
`StemApp.getGroupStatus(...)` or `StemClient.getGroupStatus(...)` before
retrying. If you are operating below the runtime layer, read the raw backend
directly.

## Dependency semantics

- **Chains** model parent → child dependencies: each step is enqueued only after
  the previous one succeeds.
- **Groups** model fan-out dependencies: a group is “complete” once all child
  tasks finish. The expected count is stored in the backend.
- **Chords** combine both: a callback depends on the entire group reaching a
  terminal state and the configured `ChordPolicy` being satisfied.

## Child result retrieval

- `Canvas.group` returns a `GroupDispatch` with a result stream for each child.
- `Canvas.chord` preserves the original signature order when building
  `chordResults`, so you can map results back to inputs deterministically.
- `StemApp.getGroupStatus(...)` and `StemClient.getGroupStatus(...)` return the
  latest status for each child task. Use `status.resultValues<T>()` for scalar
  child results or `status.resultJson(...)` / `status.resultAs(codec: ...)` for
  DTO payloads before dropping down to raw backend reads.

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
