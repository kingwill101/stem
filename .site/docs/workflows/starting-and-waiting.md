---
title: Starting and Waiting
---

Workflow runs are started through the runtime, through `StemWorkflowApp`, or
through typed workflow refs.

## Start by workflow name

```dart title="bin/run_workflow.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-run

```

Use `params:` to supply workflow input and
`WorkflowCancellationPolicy` to cap wall-clock runtime or maximum suspension
time.

That low-level API is useful when workflow names come from config or external
input. For workflows you define in code, prefer a typed workflow ref instead.

## Start through manual workflow refs

Manual `Flow(...)` and `WorkflowScript(...)` definitions can derive a typed ref
without repeating the workflow-name string:

```dart
const approvalDraftCodec = PayloadCodec<ApprovalDraft>.json(
  decode: ApprovalDraft.fromJson,
  typeName: 'ApprovalDraft',
);

final approvalsRef = approvalsFlow.refCodec<ApprovalDraft>(
  paramsCodec: approvalDraftCodec,
);

final runId = await approvalsRef.start(
  workflowApp,
  params: const ApprovalDraft(documentId: 'doc-42'),
);

final result = await approvalsRef.waitFor(workflowApp, runId);
```

Use this path when you want the same typed start/wait surface as generated
workflow refs, but the workflow itself is still hand-written.

When you want to add advanced start options, keep using the direct typed ref
helpers:

```dart
final runId = await approvalsRef.start(
  workflowApp,
  params: const ApprovalDraft(documentId: 'doc-42'),
  parentRunId: 'parent-run',
  ttl: const Duration(hours: 1),
  cancellationPolicy: const WorkflowCancellationPolicy(
    maxRuntime: Duration(minutes: 10),
  ),
);
```

`refJson(...)` is the shortest manual DTO path when the params already have
`toJson()`, or when the final result also needs a `Type.fromJson(...)`
decoder. Use `refVersionedJson(...)` when the persisted start payload should
carry an explicit `__stemPayloadVersion`. Use `refCodec(...)` when you need a
custom `PayloadCodec<T>`. Workflow params still need to encode to a
string-keyed map (typically `Map<String, dynamic>`) because they are stored as
JSON-shaped data.

Inside manual flow steps and script checkpoints, prefer
`ctx.param<T>()` / `ctx.requiredParam<T>()` for workflow start params and
`ctx.previousValue<T>()` / `ctx.requiredPreviousValue<T>()` over repeating raw
`previousResult as ...` casts.

If a manual flow or script returns a DTO, prefer `Flow.json(...)` or
`WorkflowScript.json(...)` in the common `toJson()` / `Type.fromJson(...)`
case. Use `Flow.codec(...)` or `WorkflowScript.codec(...)` when the result
needs a custom payload codec.
When the persisted workflow result or suspension payload carries an explicit
`__stemPayloadVersion`, use `workflowResult.payloadVersionedJson(...)`,
`runState.resultVersionedJson(...)`, or
`runState.suspensionPayloadVersionedJson(...)` on the low-level snapshots.
Those read-side helpers take `defaultVersion:` as the fallback for older
payloads that do not yet carry a stored version marker.

For workflows without start params, start directly from the flow or script
itself with `start(...)` or `startAndWait(...)`. When you need an explicit
low-level transport object for `startWorkflowCall(...)`, build it with
`ref0().buildStart(...)`. Treat `WorkflowStartCall` as the explicit low-level
transport object, not the normal happy path. Use `ref0()` when another API
specifically needs a `NoArgsWorkflowRef`.

When you need to adjust an explicit start request after construction, prefer
`ref.buildStart(...)` plus `copyWith(...)`.

## Wait for completion

For workflows defined in code, prefer direct workflow helpers or typed refs
like `ordersFlow.startAndWait(...)` and
`StemWorkflowDefinitions.orders.startAndWait(...)`.

`waitForCompletion<T>` is the low-level completion API for name-based runs. It
polls the store until the run finishes or the caller times out. For DTO
results, prefer `decodeJson:` for plain DTOs or `decodeVersionedJson:` when
the persisted payload carries an explicit schema version.
If you already have a raw `WorkflowResult<Object?>`, use
`result.payloadJson(...)` or `result.payloadAs(codec: ...)` to decode the
stored workflow result without another cast/closure.
If you are inspecting the underlying `RunState` directly, use
`state.paramsJson(...)`, `state.paramsAs(codec: ...)`,
`state.resultJson(...)`, `state.resultAs(codec: ...)`,
`state.resultVersionedJson(...)`, `state.suspensionPayloadJson(...)`,
`state.suspensionPayloadVersionedJson(...)`,
`state.lastErrorJson(...)`, `state.runtimeJson(...)`,
`state.cancellationDataJson(...)`, or `state.suspensionPayloadAs(codec: ...)`
instead of manual raw-map casts.
Workflow run detail views expose the same convenience surface via
`runView.paramsJson(...)`, `runView.paramsAs(codec: ...)`,
`runView.resultJson(...)`, `runView.resultAs(codec: ...)`,
`runView.resultVersionedJson(...)`, `runView.suspensionPayloadJson(...)`,
`runView.suspensionPayloadVersionedJson(...)`, `runView.lastErrorJson(...)`,
`runView.runtimeJson(...)`, and `runView.suspensionPayloadAs(codec: ...)`.
Checkpoint entries from `viewCheckpoints(...)` and
`WorkflowCheckpointView.fromEntry(...)` expose the same surface via
`entry.valueJson(...)`, `entry.valueVersionedJson(...)`, and
`entry.valueAs(codec: ...)`.

Use the returned `WorkflowResult<T>` when you need:

- `value` for a completed run
- `requiredValue()` when completion is already guaranteed and you want a
  fail-fast typed read
- `status` for partial progress
- `timedOut` to decide whether to keep polling

## Start through generated workflow refs

When you use `stem_builder`, generated workflow refs remove the raw
workflow-name strings and give you one typed handle for both start and wait:

```dart
final result = await StemWorkflowDefinitions.userSignup.startAndWait(
  workflowApp,
  params: 'user@example.com',
);
```

The same definitions work on `WorkflowRuntime` by passing the runtime as the
`WorkflowCaller`:

```dart
final runId = await StemWorkflowDefinitions.userSignup.start(
  runtime,
  params: 'user@example.com',
);
```

When you already have a `WorkflowCaller` like `FlowContext`,
`WorkflowScriptStepContext`, `WorkflowRuntime`, or `StemWorkflowApp`, prefer
the direct typed ref helpers, even when you need start overrides:

```dart
final result = await StemWorkflowDefinitions.userSignup.startAndWait(
  context,
  params: 'user@example.com',
  ttl: const Duration(hours: 1),
  timeout: const Duration(seconds: 5),
);
```

If you still need the run identifier for inspection or operator tooling, read
it from `result.runId`.

Keep `ref.buildStart(...)` for the rarer cases where you need to assemble or
adjust an explicit start request before dispatch.

## Parent runs and TTL

`WorkflowRuntime.startWorkflow(...)`, `startWorkflowJson(...)`, and
`startWorkflowVersionedJson(...)` also support:

- `parentRunId` when one workflow needs to track provenance from another run
- `ttl` when you want run metadata to expire after a bounded retention period

Those are advanced controls. Most applications only need `params:` and an
optional cancellation policy.
