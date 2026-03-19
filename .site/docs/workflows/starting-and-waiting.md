---
title: Starting and Waiting
---

Workflow runs are started through the runtime or through `StemWorkflowApp`.

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

## Start through generated helpers

When you use `stem_builder`, generated extension methods remove the raw
workflow-name strings:

```dart
final runId = await workflowApp.startUserSignup(email: 'user@example.com');
final result = await workflowApp.waitForCompletion<Map<String, Object?>>(runId);
```

These starters also exist on `WorkflowRuntime` when you want to work below the
`StemWorkflowApp` abstraction.

## Parent runs and TTL

`WorkflowRuntime.startWorkflow(...)` also supports:

- `parentRunId` when one workflow needs to track provenance from another run
- `ttl` when you want run metadata to expire after a bounded retention period

Those are advanced controls. Most applications only need `params:` and an
optional cancellation policy.
