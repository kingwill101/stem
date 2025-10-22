---
title: Observability & Recovery
sidebar_label: Recovery
sidebar_position: 4
slug: /operations/recovery
---

This guide covers day-to-day diagnostics for Stem deployments: how to inspect
running workflows, surface failures, and replay work safely.

## Inspecting groups and chords

Each group or chord stores its state in the result backend.

```bash
# List pending groups (requires STEM_RESULT_BACKEND_URL)
stem observe groups

# Inspect a specific group or chord
stem observe groups --id <groupId>
```

The command displays each branch with its latest `TaskState`, attempt count, and
failure metadata. Combine it with `stem observe metrics` to verify whether the
system is progressing or stalling.

## Dead Letter Queue remediation

1. List recent failures for a queue:
   ```bash
   stem dlq list --queue greetings --limit 20
   ```
2. Inspect an entry before replaying:
   ```bash
   stem dlq show --queue greetings --id <taskId>
   ```
3. Replay in batches:
   ```bash
   stem dlq replay --queue greetings --limit 10 --yes
   ```
4. Purge poison messages only after you understand the root cause:
   ```bash
   stem dlq purge --queue greetings --yes
   ```

> Tip: pair DLQ commands with the result backend. `stem observe groups` updates
> as replayed branches succeed.

## Monitoring beat schedules

Use the CLI to audit upcoming and recent runs:

```bash
stem schedule list
stem schedule dry-run --id cleanup-temp --count 5
```

If a schedule misbehaves, you can run it manually:

```bash
stem schedule dry-run --id cleanup-temp --spec "every:5m"
stem schedule apply --file schedules.yaml --yes
```

## Automating health checks

In addition to the CLI, the following signals should feed dashboards and alerts:

- `stem.tasks.signature_invalid` spikes
- Dead letter queue growth (`stem.dlq.depth`)
- Beat jitter/lock metrics (`stem.scheduler.lock.*`)
- Heartbeat gaps (`stem.worker.heartbeat.missed`)

Hook these into your monitoring platform to page operators promptly.
