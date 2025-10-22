---
title: CLI & Control Plane
sidebar_label: CLI & Control
sidebar_position: 8
slug: /core-concepts/cli-control
---

The `stem` CLI complements the programmatic APIs—use it to enqueue test jobs,
inspect state, and manage workers.

## Enqueue tasks

```bash
stem enqueue hello.print \
  --args '{"name":"CLI"}' \
  --registry lib/main.dart \
  --broker redis://localhost:6379
```

## Observe tasks and groups

```bash
stem observe tasks list --broker "$STEM_BROKER_URL"
stem observe groups --backend "$STEM_RESULT_BACKEND_URL"
```

## Worker control commands

```bash
stem worker ping --broker "$STEM_BROKER_URL"
stem worker stats --broker "$STEM_BROKER_URL"
stem worker revoke --broker "$STEM_BROKER_URL" --task-id <id>
stem worker shutdown --broker "$STEM_BROKER_URL" --mode warm
```

Combine with programmatic signals for richer telemetry (see
[Worker Control CLI](../workers/worker-control.md)).

## Scheduler

```bash
stem scheduler start \
  --broker "$STEM_BROKER_URL" \
  --schedule config/schedules.yaml \
  --registry lib/main.dart
```

## Health checks

```bash
stem health \
  --broker "$STEM_BROKER_URL" \
  --backend "$STEM_RESULT_BACKEND_URL" \
  --schedule-store "$STEM_SCHEDULE_STORE_URL"
```

The command exits non-zero when connectivity, TLS, or signing checks fail—ideal
for CI/CD gates.

Keep the CLI handy when iterating on the code examples in the feature guides.
