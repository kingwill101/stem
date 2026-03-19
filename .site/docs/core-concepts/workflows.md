---
title: Workflows
sidebar_label: Workflows
sidebar_position: 8
slug: /core-concepts/workflows
---

Stem Workflows let you orchestrate multi-step business processes with durable
state, typed results, automatic retries, and event-driven resumes. The
`StemWorkflowApp` helper wires together a `Stem` instance, workflow store,
event bus, and runtime so you can start runs, monitor progress, and interact
with suspended steps from one place.

This page is now the short orientation page. The full workflow manual lives in
the top-level [Workflows](../workflows/index.md) section.

## Start there for the full workflow guide

- [Getting Started](../workflows/getting-started.md)
- [Flows and Scripts](../workflows/flows-and-scripts.md)
- [Annotated Workflows](../workflows/annotated-workflows.md)
- [Context and Serialization](../workflows/context-and-serialization.md)
- [How It Works](../workflows/how-it-works.md)
- [Observability](../workflows/observability.md)

## Runtime overview

```dart title="bin/workflows.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-app-create

```

Start the runtime once the app is constructed:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-app-start

```

`StemWorkflowApp` exposes:

- `runtime` – registers `Flow`/`WorkflowScript` definitions and dequeues runs.
- `store` – persists checkpoints, suspension metadata, and results.
- `eventBus` – emits topics that resume waiting steps.
- `app` – the underlying `StemApp` (broker + result backend + worker).

## What makes workflows different from tasks

- workflow runs persist durable state in a workflow store
- steps or checkpoints can suspend on time or external events
- resumption happens through persisted watchers and due-run scheduling
- admin tooling can inspect runs even after worker restarts

## Flow versus script

- flows: declared steps are the execution plan
- scripts: `run(...)` is the execution plan
- script checkpoints are durable replay boundaries plus manifest metadata

The details now live in [Flows and Scripts](../workflows/flows-and-scripts.md).
