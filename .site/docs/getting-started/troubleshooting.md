---
title: Troubleshooting
sidebar_label: Troubleshooting
sidebar_position: 7
slug: /getting-started/troubleshooting
---

Common issues when getting started with Stem and how to resolve them.

## Worker starts but no tasks are processed

Checklist:

- Make sure the producer and worker share the same broker URL.
- Confirm the worker is subscribed to the queue you are enqueueing into.
- If routing is enabled, verify the routing file and default queue.

Helpful commands:

```bash
stem worker status --broker "$STEM_BROKER_URL" --result-backend "$STEM_RESULT_BACKEND_URL"
stem worker inspect --broker "$STEM_BROKER_URL"
```

## Control commands return no replies

This usually means the control broadcast channel is not being consumed.

Checklist:

- Ensure the worker is running and connected to the same broker.
- If you use a custom namespace, pass `--namespace` to CLI commands.
- Verify that the broker supports broadcast/control channels.

## Task retries instantly or too quickly

Checklist:

- Confirm your task’s `TaskOptions` (`maxRetries`, `visibilityTimeout`).
- Ensure the broker supports delayed deliveries (`notBefore`).
- Check broker clock drift if delays feel inconsistent.

## Connection refused

Checklist:

- Verify Redis/Postgres is running and reachable.
- Confirm the URL scheme (`redis://`, `postgres://`).
- Ensure Docker ports are mapped (`-p 6379:6379`, `-p 5432:5432`).

## Still stuck?

- Review the [Observability & Ops](./observability-and-ops.md) guide for
  heartbeats, DLQ inspection, and control commands.
- Check the runnable examples under `packages/stem/example/`.
