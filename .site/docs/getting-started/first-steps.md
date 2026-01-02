---
title: First Steps
sidebar_label: First Steps
sidebar_position: 3
slug: /getting-started/first-steps
---

This walkthrough stays in-memory so you can learn the pipeline without running
external services. It defines a task, starts a worker, enqueues a message, then
verifies the result inside a single Dart process.

## 1. Define a task handler

Create a task handler (StemApp will register it for you):

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/first_steps.dart#first-steps-task

```

## 2. Bootstrap the in-memory runtime

Use `StemApp` to create the broker, backend, and worker in memory:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/first_steps.dart#first-steps-bootstrap

```

## 3. Enqueue from a producer

Enqueue a task from the same process:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/first_steps.dart#first-steps-enqueue

```

## 4. Fetch task results

Result backends store the task state and payload:

```dart file=<rootDir>/../packages/stem/example/docs_snippets/lib/first_steps.dart#first-steps-results

```

## Choose a broker and backend

Stem lets you mix brokers and backends. Use this quick guide when selecting
your first deployment:

| Need | Broker | Backend |
| ---- | ------ | ------- |
| Lowest latency, simplest ops | Redis Streams | Redis or Postgres |
| SQL visibility & durability | Postgres broker | Postgres |
| Local dev & tests | In-memory | In-memory |

Decision shortcuts:

- Start with **Redis** unless your org mandates another transport.
- Use **Postgres** when you want a single durable store or SQL-level visibility.
- Use **in-memory** only for local tests/demos.

For more detail, see [Broker Overview](../brokers/overview.md) and
[Persistence](../core-concepts/persistence.md).

## Install

- Install Stem and the CLI as shown in [Quick Start](./quick-start.md).
- Ensure `stem --version` runs in your shell.

## App setup

- Register tasks and options via `StemApp` or a shared registry (see
  [Tasks & Retries](../core-concepts/tasks.md)).
- Wire producers with the same task list/registry (see
  [Producer API](../core-concepts/producer.md)).

## Run a worker

- Start a worker against your broker and queues (see
  [Connect to Infrastructure](./developer-environment.md)).
- Use [Worker Control CLI](../workers/worker-control.md) to confirm it is
  responding.

## Call a task

- Enqueue from your app or the CLI (see
  [Producer API](../core-concepts/producer.md)).

## Keeping results

- Configure a result backend for stored task results and groups (see
  [Persistence](../core-concepts/persistence.md)).

## Configuration

- Use `STEM_*` environment variables for brokers, routing, scheduling, and
  signing (see [CLI & Control](../core-concepts/cli-control.md)).
- Define routing rules in `STEM_ROUTING_CONFIG` for multi-queue setups (see
  [Routing](../core-concepts/routing.md)).

## Troubleshooting

- Diagnose common errors in
  [Troubleshooting](./troubleshooting.md).

## Next steps

- Move to [Connect to Infrastructure](./developer-environment.md) to wire
  routing, autoscaling, and multi-queue workers.
- Review [Broker Overview](../brokers/overview.md) for transport tradeoffs.
- Explore [Persistence](../core-concepts/persistence.md) to store results in
  Redis or Postgres.
