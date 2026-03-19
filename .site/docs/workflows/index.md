---
title: Workflows
slug: /workflows
sidebar_position: 0
---

Stem workflows are the durable orchestration layer on top of the normal Stem
task runtime. They let you model multi-step business processes, suspend on
time or external events, resume on another worker, and inspect the full run
state from the store, CLI, or dashboard.

Use this section as the main workflow manual. The older
[`Core Concepts > Workflows`](../core-concepts/workflows.md) page now just
orients you and links back here.

## Pick a workflow style

- **Flow**: a declared sequence of durable steps. Use this when you want the
  workflow structure to be the source of truth.
- **WorkflowScript**: a durable async function. Use this when normal Dart
  control flow should define the execution plan.
- **Annotated workflows with `stem_builder`**: use annotations and generated
  starters when you want plain method signatures and less string-based wiring.

## Read this section in order

- [Getting Started](./getting-started.md) shows the runtime bootstrap and the
  basic start/wait lifecycle.
- [Flows and Scripts](./flows-and-scripts.md) explains the execution model
  difference between declared steps and script checkpoints.
- [Starting and Waiting](./starting-and-waiting.md) covers named starts,
  generated starters, results, and cancellation policies.
- [Suspensions and Events](./suspensions-and-events.md) covers `sleep`,
  `awaitEvent`, due runs, and external resume flows.
- [Annotated Workflows](./annotated-workflows.md) covers `stem_builder`,
  context injection, and generated starters.
- [Context and Serialization](./context-and-serialization.md) documents where
  context objects are injected and what parameter shapes are supported.
- [Errors, Retries, and Idempotency](./errors-retries-and-idempotency.md)
  explains replay expectations and how to keep durable code safe.
- [How It Works](./how-it-works.md) explains the runtime, store, leases, and
  manifests.
- [Observability](./observability.md) covers logs, dashboard views, and store
  inspection.
- [Troubleshooting](./troubleshooting.md) collects the workflow-specific
  failure modes you are likely to hit first.

## Runtime bootstrap

```dart title="bin/workflows.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-app-create

```

```dart title="bin/workflows.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-app-start

```

`StemWorkflowApp` is the recommended entrypoint because it wires:

- the underlying `StemApp`
- the workflow runtime
- the workflow store
- the workflow event bus
- the managed worker that executes the internal `stem.workflow.run` task

If you already own a `StemClient`, you can attach workflow support through that
shared client instead of constructing a second app boundary:

```dart
final client = await StemClient.fromUrl('memory://');
final workflowApp = await client.createWorkflowApp(
  flows: [ApprovalsFlow.flow],
  scripts: [retryScript],
);
```

If your service already owns a `StemApp`, reuse it directly with
`StemWorkflowApp.create(stemApp: ..., flows: ..., scripts: ..., tasks: ...)`
rather than bootstrapping a second broker/backend/task boundary.
