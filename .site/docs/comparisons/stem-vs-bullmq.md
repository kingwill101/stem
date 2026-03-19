---
title: Stem vs BullMQ
sidebar_label: Stem vs BullMQ
sidebar_position: 1
slug: /comparisons/stem-vs-bullmq
---

This page is the canonical Stem comparison matrix for BullMQ-style features.
It focuses on capability parity, not API-level compatibility.

**As of:** March 18, 2026

## Status semantics

| Status | Meaning |
| --- | --- |
| `✓` | Functionally equivalent built-in capability exists in Stem. |
| `~` | Partial or non-isomorphic capability exists, but semantics differ from BullMQ/BullMQ-Pro. |
| `✗` | No built-in capability in Stem today. |

## Feature matrix

| BullMQ row | Stem | Rationale (with evidence) |
| --- | --- | --- |
| Backend | `✓` | Stem supports multiple backends/adapters (Redis, Postgres, SQLite, in-memory). See [Broker Overview](../brokers/overview.md) and [Developer Environment](../getting-started/developer-environment.md). |
| Observables | `✓` | Stem has built-in metrics, tracing, and lifecycle signals. See [Observability](../core-concepts/observability.md) and [Signals](../core-concepts/signals.md). |
| Group Rate Limit | `✓` | Stem supports group-scoped rate limiting via `TaskOptions.groupRateLimit`, `groupRateKey`, and `groupRateKeyHeader`. See [Rate Limiting](../core-concepts/rate-limiting.md). |
| Group Support | `✓` | Stem provides `Canvas.group` and `Canvas.chord` primitives. See [Canvas Patterns](../core-concepts/canvas.md). |
| Batches Support | `✓` | Stem exposes first-class batch APIs (`submitBatch`, `inspectBatch`) with durable batch lifecycle status. See [Canvas Patterns](../core-concepts/canvas.md). |
| Parent/Child Dependencies | `✓` | Stem supports dependency composition through chains, groups/chords, and durable workflow stages. See [Canvas Patterns](../core-concepts/canvas.md) and [Workflows](../workflows/index.md). |
| Deduplication (Debouncing) | `~` | `TaskOptions.unique` prevents duplicate enqueue claims, but semantics are lock/TTL-based rather than BullMQ-native dedupe APIs. See [Uniqueness](../core-concepts/uniqueness.md). |
| Deduplication (Throttling) | `~` | `uniqueFor` and lock TTL windows approximate throttling behavior, but are not a direct BullMQ equivalent. See [Uniqueness](../core-concepts/uniqueness.md). |
| Priorities | `✓` | Stem supports task priority and queue priority ranges. See [Tasks](../core-concepts/tasks.md) and [Routing](../core-concepts/routing.md). |
| Concurrency | `✓` | Workers support configurable concurrency and isolate pools. See [Workers](../workers/index.md) and [Worker Control](../workers/worker-control.md). |
| Delayed jobs | `✓` | Delayed execution is supported via enqueue options and broker scheduling. See [Quick Start](../getting-started/quick-start.md) and [Broker Overview](../brokers/overview.md). |
| Global events | `✓` | Stem exposes global lifecycle events through `StemSignals`, plus queue-scoped custom events through `QueueEvents`. See [Signals](../core-concepts/signals.md) and [Queue Events](../core-concepts/queue-events.md). |
| Rate Limiter | `✓` | Stem supports per-task rate limits with pluggable limiter backends. See [Rate Limiting](../core-concepts/rate-limiting.md). |
| Pause/Resume | `✓` | Stem provides queue pause/resume commands (`stem worker pause`, `stem worker resume`) and persistent pause state when a revoke store is configured. See [Worker Control](../workers/worker-control.md). |
| Sandboxed worker | `~` | Stem supports isolate-based execution boundaries, but this is not equivalent to BullMQ's Node child-process sandbox model. See [Worker Control](../workers/worker-control.md). |
| Repeatable jobs | `✓` | Stem Beat supports interval, cron, solar, and clocked schedules. See [Scheduler](../scheduler/index.md) and [Beat Scheduler Guide](../scheduler/beat-guide.md). |
| Atomic ops | `~` | Stem includes atomic behavior in specific stores/flows, but end-to-end transactional guarantees (for all enqueue/ack/result paths) are not universally built-in. See [Tasks idempotency guidance](../core-concepts/tasks.md#idempotency-checklist) and [Best Practices](../getting-started/best-practices.md). |
| Persistence | `✓` | Stem persists task/workflow/schedule state through pluggable backends/stores. See [Persistence & Stores](../core-concepts/persistence.md). |
| UI | `~` | Stem includes an experimental dashboard, not a fully mature operator UI parity target yet. See [Dashboard](../core-concepts/dashboard.md). |
| Optimized for | `~` | Stem is optimized for jobs/messages plus durable workflow orchestration, not only queue semantics. See [Core Concepts](../core-concepts/index.md) and [Workflows](../workflows/index.md). |

## Update policy

When this matrix changes:

1. Update the **As of** date.
2. Keep row names aligned with BullMQ terminology.
3. Update rationale links so every status remains auditable.

## BullMQ events parity notes

Stem supports the two common BullMQ event-listening styles:

| BullMQ concept | Stem equivalent |
| --- | --- |
| `QueueEvents` listeners | `QueueEvents` + `QueueEventsProducer` (queue-scoped custom events) |
| Custom queue events | `producer.emit(queue, eventName, payload, headers, meta)` |
| Worker-specific event listeners | `StemSignals` convenience APIs with `workerId` filters (`onWorkerReady`, `onWorkerInit`, `onTaskFailure`, `onControlCommandCompleted`, etc.) |
