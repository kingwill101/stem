---
title: Starting and Waiting
---

Workflow runs are started through the runtime, through `StemWorkflowApp`, or
through generated workflow refs.

## Start by workflow name

```dart title="bin/run_workflow.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-run

```

Use `params:` to supply workflow input and
`WorkflowCancellationPolicy` to cap wall-clock runtime or maximum suspension
time.

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
final result = await StemWorkflowDefinitions.userSignup
    .call((email: 'user@example.com'))
    .startAndWaitWithApp(workflowApp);
```

The same definitions work on `WorkflowRuntime` through
`.startWithRuntime(runtime)`.

If you still need the run identifier for inspection or operator tooling, read
it from `result.runId`.

## Parent runs and TTL

`WorkflowRuntime.startWorkflow(...)` also supports:

- `parentRunId` when one workflow needs to track provenance from another run
- `ttl` when you want run metadata to expire after a bounded retention period

Those are advanced controls. Most applications only need `params:` and an
optional cancellation policy.
