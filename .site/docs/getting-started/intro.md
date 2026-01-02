---
title: Welcome to Stem
sidebar_label: Introduction
sidebar_position: 1
slug: /
aliases:
  - /getting-started/intro
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Stem is a Dart-native background work platform that gives you Celery‑level
capabilities without leaving the Dart ecosystem. This onboarding path assumes
you have never touched Stem before and walks you from “what is this?” to “I can
ship a production deployment.”

## What is a task queue?

A task queue lets you push work to background workers instead of blocking your
web or API process. The core pipeline looks like:

```
Producer → Broker → Worker → Result Backend
```

- **Architecture at a glance**

![Task queue pipeline](/img/task-queue-pipeline.svg)

- **Producer** enqueues a task (e.g. send email).
- **Broker** stores and delivers tasks to workers.
- **Worker** executes tasks and reports status.
- **Result backend** keeps history and outputs.

In Stem, you can mix and match brokers and backends (for example, Redis for
fast delivery and Postgres for durable results).

## A minimal Stem pipeline

The core objects are a task handler, a worker, and a producer. This example
keeps everything in a single file so you can see the moving parts together.

<Tabs>
<TabItem value="task" label="Define a task handler">

```dart title="stem_example.dart" file=<rootDir>/../packages/stem/example/stem_example.dart#getting-started-task-definition

```

</TabItem>
<TabItem value="runtime" label="Set up the broker, backend, and worker">

```dart title="stem_example.dart" file=<rootDir>/../packages/stem/example/stem_example.dart#getting-started-runtime-setup

```

</TabItem>
<TabItem value="enqueue" label="Start the worker and enqueue work">

```dart title="stem_example.dart" file=<rootDir>/../packages/stem/example/stem_example.dart#getting-started-enqueue

```

</TabItem>
</Tabs>

## What You’ll Unlock

- **Core pipeline** – Enqueue tasks with delays, priorities, retries, rate
  limits, and canvas compositions, backed by result stores.
- **Workers & signals** – Operate isolate-based workers, autoscale them,
  and react to lifecycle signals.
- **Observability & tooling** – Stream metrics, traces, heartbeats, and inspect
  queues, DLQs, and schedules from the CLI.
- **Security & deployment** – Sign payloads, enable TLS, and run Stem via
  systemd/SysV or the multi-worker CLI wrapper.
- **Enablement & quality** – Use runnable examples, runbooks, and automated
  quality gates to keep deployments healthy.

## Prerequisites

- Dart **3.3+** installed (`dart --version`).
- Access to the Dart pub cache (`dart pub ...`).
- Optional but recommended: Docker Desktop or another container runtime for
  local Redis/Postgres instances.
- Optional: Node.js 18+ if you plan to run the documentation site locally.
- A text editor capable of running Dart tooling (VS Code, IntelliJ, Neovim).

## Onboarding Path

1. **[Quick Start](./quick-start.md)** – Build and run your first Stem worker
   entirely in memory while you learn the task pipeline primitives.
2. **[First Steps](./first-steps.md)** – Use Redis to run producers and workers
   in separate processes, then fetch results.
3. **[Connect to Infrastructure](./developer-environment.md)** – Point Stem at
   Redis/Postgres, run workers/Beat across processes, and try routing/canvas
   patterns.
4. **[Observe & Operate](./observability-and-ops.md)** – Enable telemetry,
   inspect heartbeats, replay DLQ entries, and wire control commands.
5. **[Prepare for Production](./production-checklist.md)** – Enable signing,
   TLS, daemonization, and automated quality gates before launch.

Each step includes copy-pasteable code or CLI examples and ends with pointers
to deeper reference material.

> **Next:** Jump into the [Quick Start](./quick-start.md) to see Stem in action.
