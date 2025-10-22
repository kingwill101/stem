---
title: Welcome to Stem
sidebar_label: Introduction
sidebar_position: 1
slug: /getting-started/intro
---

Stem is a Dart-native background work platform that gives you Celery‑level
capabilities without leaving the Dart ecosystem. This onboarding path assumes
you have never touched Stem before and walks you from “what is this?” to “I can
ship a production deployment.”

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
2. **[Connect to Infrastructure](./developer-environment.md)** – Point Stem at
   Redis/Postgres, run workers/Beat across processes, and try routing/canvas
   patterns.
3. **[Observe & Operate](./observability-and-ops.md)** – Enable telemetry,
   inspect heartbeats, replay DLQ entries, and wire control commands.
4. **[Prepare for Production](./production-checklist.md)** – Enable signing,
   TLS, daemonization, and automated quality gates before launch.

Each step includes copy-pasteable code or CLI examples and ends with pointers
to deeper reference material.

> **Next:** Jump into the [Quick Start](./quick-start.md) to see Stem in action.
