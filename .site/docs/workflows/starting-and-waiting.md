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
const approvalDraftCodec = PayloadCodec<ApprovalDraft>(
  encode: (value) => value.toJson(),
  decode: (payload) => ApprovalDraft.fromJson(
    Map<String, Object?>.from(payload as Map),
  ),
);

final approvalsRef = approvalsFlow.refWithCodec<ApprovalDraft>(
  paramsCodec: approvalDraftCodec,
);

final runId = await approvalsRef.startWith(
  workflowApp,
  const ApprovalDraft(documentId: 'doc-42'),
);

final result = await approvalsRef.waitFor(workflowApp, runId);
```

Use this path when you want the same typed start/wait surface as generated
workflow refs, but the workflow itself is still hand-written.

When you want to add advanced start options fluently, use the workflow start
builder:

```dart
final runId = await approvalsRef
    .startBuilder(const ApprovalDraft(documentId: 'doc-42'))
    .parentRunId('parent-run')
    .ttl(const Duration(hours: 1))
    .cancellationPolicy(
      const WorkflowCancellationPolicy(maxRuntime: Duration(minutes: 10)),
    )
    .startWith(workflowApp);
```

`refWithCodec(...)` is the manual DTO path. The codec still needs to encode to
`Map<String, Object?>` because workflow params are stored as a map.

For workflows without start params, derive `ref0()` instead and start them
directly from the no-args ref.

## Wait for completion

`waitForCompletion<T>` polls the store until the run finishes or the caller
times out.

Use the returned `WorkflowResult<T>` when you need:

- `value` for a completed run
- `status` for partial progress
- `timedOut` to decide whether to keep polling

## Start through generated workflow refs

When you use `stem_builder`, generated workflow refs remove the raw
workflow-name strings and give you one typed handle for both start and wait:

```dart
final result = await StemWorkflowDefinitions.userSignup.startAndWaitWith(
  workflowApp,
  'user@example.com',
);
```

The same definitions work on `WorkflowRuntime` by passing the runtime as the
`WorkflowCaller`:

```dart
final runId = await StemWorkflowDefinitions.userSignup.startWith(
  runtime,
  'user@example.com',
);
```

When you already have a `WorkflowCaller` like `FlowContext`,
`WorkflowScriptStepContext`, `WorkflowRuntime`, or `StemWorkflowApp`, prefer
the caller-bound fluent builder:

```dart
final result = await context
    .startWorkflowBuilder(
      definition: StemWorkflowDefinitions.userSignup,
      params: 'user@example.com',
    )
    .ttl(const Duration(hours: 1))
    .startAndWait(timeout: const Duration(seconds: 5));
```

If you still need the run identifier for inspection or operator tooling, read
it from `result.runId`.

## Parent runs and TTL

`WorkflowRuntime.startWorkflow(...)` also supports:

- `parentRunId` when one workflow needs to track provenance from another run
- `ttl` when you want run metadata to expire after a bounded retention period

Those are advanced controls. Most applications only need `params:` and an
optional cancellation policy.
