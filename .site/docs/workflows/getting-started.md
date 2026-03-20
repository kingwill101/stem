---
title: Getting Started
sidebar_position: 1
---

This is the quickest path to a working durable workflow in Stem.

## 1. Create a workflow app

```dart title="bin/workflows.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-app-create

```

Pass normal task handlers through `tasks:` if the workflow also needs to
enqueue regular Stem tasks.

## 2. Start the managed worker

```dart title="bin/workflows.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-app-start

```

`StemWorkflowApp.start()` starts both the runtime and the underlying worker.
The managed worker subscribes to the workflow orchestration queue, so you do
not need to manually register the internal `stem.workflow.run` task.

If you prefer a minimal example, `startWorkflow(...)` also lazy-starts the
runtime and managed worker on first use. Explicit `start()` is still the better
choice when you want deterministic application lifecycle control.

## 3. Start a run and wait for the result

```dart title="bin/run_workflow.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-run

```

The returned `WorkflowResult<T>` includes:

- the decoded `value`
- the persisted `RunState`
- a `timedOut` flag when the caller stops waiting before the run finishes

## 4. Reuse existing bootstrap when needed

```dart title="bin/workflows_client.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-client

```

Use `StemClient` when one service wants to own broker, backend, and workflow
setup in one place. The clean path there is `client.createWorkflowApp(...)`.

If your service already owns a `StemApp`, layer workflows on top of it with
`stemApp.createWorkflowApp(...)`. That path reuses the current worker, so the
underlying app must already subscribe to the workflow queue plus the task
queues your workflows need.

## 5. Move to the right next page

- If you need a mental model first, read [Flows and Scripts](./flows-and-scripts.md).
- If you want the decorator/codegen path, read
  [Annotated Workflows](./annotated-workflows.md).
- If you need to suspend and resume runs, read
  [Suspensions and Events](./suspensions-and-events.md).
