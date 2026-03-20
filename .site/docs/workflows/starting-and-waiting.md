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

When you want to add advanced start options fluently, use the workflow start
builder:

```dart
final runId = await approvalsRef
    .prepareStart(const ApprovalDraft(documentId: 'doc-42'))
    .parentRunId('parent-run')
    .ttl(const Duration(hours: 1))
    .cancellationPolicy(
      const WorkflowCancellationPolicy(maxRuntime: Duration(minutes: 10)),
    )
    .start(workflowApp);
```

`refJson(...)` is the shortest manual DTO path when the params or
final result already have `toJson()` and `Type.fromJson(...)`. Use
`refCodec(...)` when you need a custom `PayloadCodec<T>`. Workflow params
still need to encode to a string-keyed map (typically
`Map<String, dynamic>`) because they are stored as JSON-shaped data.

If a manual flow or script returns a DTO, prefer `decodeResultJson:` on the
definition constructor in the common `toJson()` / `Type.fromJson(...)` case.
Use `resultCodec:` only when the result needs a custom payload codec.

For workflows without start params, start directly from the flow or script
itself with `start(...)`, `startAndWait(...)`, or `prepareStart()`.
Use `ref0()` when another API specifically needs a `NoArgsWorkflowRef`.

## Wait for completion

For workflows defined in code, prefer direct workflow helpers or typed refs
like `ordersFlow.startAndWait(...)` and
`StemWorkflowDefinitions.orders.startAndWait(...)`.

`waitForCompletion<T>` is the low-level completion API for name-based runs. It
polls the store until the run finishes or the caller times out.

Use the returned `WorkflowResult<T>` when you need:

- `value` for a completed run
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

Keep `context.prepareStart(...)` for the rarer cases where you want to
assemble a start request incrementally before dispatch.

## Parent runs and TTL

`WorkflowRuntime.startWorkflow(...)` also supports:

- `parentRunId` when one workflow needs to track provenance from another run
- `ttl` when you want run metadata to expire after a bounded retention period

Those are advanced controls. Most applications only need `params:` and an
optional cancellation policy.
