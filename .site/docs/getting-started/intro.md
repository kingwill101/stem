---
title: Welcome to Stem
sidebar_label: Introduction
sidebar_position: 1
slug: /
aliases:
  - /getting-started/intro
---

Stem is a Dart-native toolkit for background tasks and durable workflows. A
task is a unit of work a worker can retry. A workflow is an orchestrated
program whose named checkpoints and waits can be resumed from a store.

## Choose your first path

| You need to… | Start here |
| --- | --- |
| Run a typed, multi-step process with `sleep` or events | [Hosted workflow quick start](./quick-start.md) |
| Put independent jobs on a queue | [Generated task first steps](./first-steps.md) |
| Decide between memory, Redis, Postgres, or SQLite | [Choosing a backend](./choosing-a-backend.md) |

The function-first API is `WorkflowHost`: define a `HostedWorkflow`, submit
typed input, and await a `HostedRun` result. The host is an application
facade, not a second execution engine.

## Source checkouts and published packages

The documentation site is built from this repository, while `dart pub add stem`
resolves the latest published package. A checkout can contain APIs that are
not in the published release yet. If an example does not resolve in a
published app, either use the release's API documentation or depend on a
specific source path while evaluating the checkout:

```yaml
dependencies:
  stem:
    path: ../packages/stem
```

Do not copy internal `package:stem/src/...` imports from repository tests or
examples into application code; use the public exports documented here.

## The execution model

For tasks, the path is `producer → broker → worker → result backend`.
`WorkflowHost.inMemory` packages the workflow app, worker, and in-memory store
for a small process-local demo. It starts the app for you and owns it until
`close()`.

In-memory state is not restart-durable. For production, create a host with
`WorkflowHost.create` and an app factory that configures a persistent adapter.
Re-register the same executable workflow definitions after a restart and use
`observe` with a saved run ID; observing does not submit a second run.

## What to remember

- Delivery and execution are **at least once**. Checkpointing reduces repeated
  work, but external effects still need idempotency keys or deduplication.
- `context.step` runs a local Dart callback. It is a workflow checkpoint, not a
  remote activity or a new worker process.
- `host.close()` stops local observation and closes resources it owns; it does
  not cancel persisted runs or forcibly interrupt Dart code.

Next: follow [Quick Start](./quick-start.md), then read
[First Steps](./first-steps.md) if your app also has generated tasks.
