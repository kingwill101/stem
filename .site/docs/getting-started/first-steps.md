---
title: First Steps
sidebar_label: First Steps
sidebar_position: 3
slug: /getting-started/first-steps
---

Use a generated task for an independent job such as an email, thumbnail, or
webhook. For a function-first, multi-step process, use the [hosted workflow
quick start](./quick-start.md).

## The task shape

A task definition describes its name and input. A generated task reference
gives application code a typed enqueue method; the worker runs the registered
handler:

```text
producer -> broker -> worker -> result backend
```

See [Tasks](../core-concepts/tasks.md) and
[Producer API](../core-concepts/producer.md) for current definition and
registration APIs. Keep generated code and the `stem_builder` dependency on
the same version. Do not mix snippets from a source checkout with a published
release.

## Reliability and local development

Task delivery and execution are at least once. A retry, lease expiry, or crash
can run a handler again. Make handlers idempotent and pass a stable
idempotency key to external systems. Task retry policy controls delivery
attempts; it is separate from a workflow action's logical retry policy.

Use an in-memory client for tests and demos only: its state is not
restart-durable. A broker and result backend are separate choices. Move to a
persistent configuration with [Choosing a backend](./choosing-a-backend.md).

For a user-facing foreground workflow, see the `stem_flutter` bindings and
[Next Steps](./next-steps.md).
