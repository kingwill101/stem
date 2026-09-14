---
title: Workflows
description: Learn typed workflows, checkpoints, durable waits, recovery, and idempotency.
slug: /workflows
sidebar_position: 0
---

Stem workflows orchestrate durable, typed functions over the normal task
runtime. Begin with [`WorkflowHost`](../getting-started/quick-start.md):
`HostedWorkflow<I, R>`, `submit`, and a typed `HostedRun<R>`.

`context.step` is a named checkpoint around a local Dart callback, not a remote
activity. Execution and external effects are at least once, so use idempotency.
`host.close()` closes owned resources and observers; it does not cancel
persisted runs or forcibly interrupt Dart code.

Choose [Flows and Scripts](./flows-and-scripts.md) for declared steps, or
[Annotated Workflows](./annotated-workflows.md) for generated refs. Then read
[Getting Started](./getting-started.md), [Starting and Waiting](./starting-and-waiting.md),
[Suspensions and Events](./suspensions-and-events.md), and
[Context and Serialization](./context-and-serialization.md).
