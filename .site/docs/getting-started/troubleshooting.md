---
title: Troubleshooting
sidebar_label: Troubleshooting
sidebar_position: 7
slug: /getting-started/troubleshooting
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

Common issues when getting started with Stem and how to resolve them.

## Worker starts but no tasks are processed

Checklist:

- Make sure the producer and worker share the same broker URL.
- Confirm the worker is subscribed to the queue you are enqueueing into.
- If routing is enabled, verify the routing file and default queue.

<Tabs>
<TabItem value="task" label="Minimal task handler">

```dart title="lib/troubleshooting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/troubleshooting.dart#troubleshooting-task

```

</TabItem>
<TabItem value="bootstrap" label="Worker + broker bootstrap">

```dart title="lib/troubleshooting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/troubleshooting.dart#troubleshooting-bootstrap

```

</TabItem>
<TabItem value="enqueue" label="Producer enqueue">

```dart title="lib/troubleshooting.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/troubleshooting.dart#troubleshooting-enqueue

```

</TabItem>
</Tabs>

Helpful commands:

```bash
stem worker stats --json
stem worker inspect
stem observe queues
```

## Routing file fails to parse

Checklist:

- Validate the routing file path and format (YAML/JSON).
- Confirm `STEM_ROUTING_CONFIG` points at the file you expect.
- Confirm the registry matches the task names referenced in the file.
- If you use queue priorities, ensure the broker supports them.

<Tabs>
<TabItem value="load" label="Load routing file">

```dart title="lib/routing.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/routing.dart#routing-load

```

</TabItem>
<TabItem value="inline" label="Inline routing registry">

```dart title="lib/routing.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/routing.dart#routing-inline

```

</TabItem>
</Tabs>

Helpful commands:

```bash
stem routing dump
stem routing dump --json
stem routing dump --sample
```

## Missing or misconfigured result backend

Symptoms: `stem observe` fails or task results never appear.

Checklist:

- Set `STEM_RESULT_BACKEND_URL` for any workflow that needs stored results.
- Ensure the backend URL uses the correct scheme (`redis://`, `postgres://`).
- Confirm the worker is configured with the same result backend.

<Tabs>
<TabItem value="redis" label="Redis result backend">

```dart title="lib/persistence.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-backend-redis

```

</TabItem>
<TabItem value="postgres" label="Postgres result backend">

```dart title="lib/persistence.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/persistence.dart#persistence-backend-postgres

```

</TabItem>
</Tabs>

Helpful commands:

```bash
stem health --backend "$STEM_RESULT_BACKEND_URL"
stem observe workers
stem observe queues
```

## TLS or signing failures

Symptoms: health checks fail or tasks land in the DLQ with signature errors.

Checklist:

- Verify `STEM_TLS_*` variables are set on every component that connects.
- Confirm `STEM_SIGNING_KEYS`/`STEM_SIGNING_PUBLIC_KEYS` match across producers and workers.
- Ensure `STEM_SIGNING_ACTIVE_KEY` is set and present in the key list.
- Check DLQ entries for `signature-invalid` reasons.

<Tabs>
<TabItem value="signed" label="Signed enqueue">

```dart title="lib/producer.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/producer.dart#producer-signed

```

</TabItem>
<TabItem value="shared-signer" label="Shared signer config">

```dart title="lib/production_checklist.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/production_checklist.dart#production-signing

```

</TabItem>
</Tabs>

Helpful commands:

```bash
stem health \
  --broker "$STEM_BROKER_URL" \
  --backend "$STEM_RESULT_BACKEND_URL"

stem dlq list --queue <queue>
stem dlq show --queue <queue> --id <task-id>
```

## Namespace mismatch

Symptoms: CLI sees no data or control commands return empty responses.

Checklist:

- Ensure all processes (producer, worker, CLI) use the same namespace string.
- For workers, confirm `STEM_WORKER_NAMESPACE` matches your CLI `--namespace`.

<Tabs>
<TabItem value="broker" label="Broker + backend namespace">

```dart title="lib/namespaces.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/namespaces.dart#namespaces-broker-backend

```

</TabItem>
<TabItem value="worker" label="Worker namespace">

```dart title="lib/namespaces.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/namespaces.dart#namespaces-worker

```

</TabItem>
</Tabs>

Helpful commands:

```bash
stem worker stats --namespace "stem"
stem worker ping --namespace "stem"
```

## Migrations or schema errors

Checklist:

- Run the migration commands shipped with the adapter (Redis/Postgres).
- Ensure your store URLs point to the migrated database/schema.
- Set `STEM_SCHEDULE_STORE_URL` before running schedule commands.

Helpful commands:

```bash
stem schedule list
```

## DLQ stalls or poison-pill tasks

Checklist:

- Inspect DLQ entries and replay only after fixing the root cause.
- For repeat failures, consider lowering retries or adding task-level guards.

Helpful commands:

```bash
stem dlq list --queue <queue>
stem dlq show --queue <queue> --id <task-id>
stem dlq replay --queue <queue> --id <task-id>
```

Example enqueue that will land in the DLQ:

```dart title="bin/producer.dart" file=<rootDir>/../packages/stem/example/dlq_sandbox/bin/producer.dart#dlq-producer-enqueue
```

## Control commands return no replies

This usually means the control broadcast channel is not being consumed.

Checklist:

- Ensure the worker is running and connected to the same broker.
- If you use a custom namespace, pass `--namespace` to CLI commands.
- Verify that the broker supports broadcast/control channels.

Helpful commands:

```bash
stem worker stats --json
stem observe workers
```

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

Helpful commands:

```bash
stem health \
  --broker "$STEM_BROKER_URL" \
  --backend "$STEM_RESULT_BACKEND_URL" \
```

## Still stuck?

- Review the [Observability & Ops](./observability-and-ops.md) guide for
  heartbeats, DLQ inspection, and control commands.
- Check the runnable examples under `packages/stem/example/`.
