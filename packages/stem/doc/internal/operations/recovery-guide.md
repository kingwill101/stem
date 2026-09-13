---
title: Observability & Recovery
sidebar_label: Recovery
sidebar_position: 4
slug: /operations/recovery
---

This guide covers day-to-day diagnostics for Stem deployments: how to inspect
running workflows, surface failures, and replay work safely.

## Workflow lease recovery

Workflow runs are protected by leases so only one worker executes a run at a
time. If a worker crashes, another worker can take over once the lease expires.

Operational checks:

- Ensure `runLeaseDuration` is **>=** your broker visibility timeout so a
  redelivered task does not get dropped before the lease expires.
- Ensure workers renew leases (`leaseExtension`) before the lease or visibility
  timeout expires.
- Keep system clocks in sync (NTP) so lease expiry is consistent across nodes.

If runs appear stuck:

1. Confirm the lease expiry is advancing in the workflow store.
2. Verify workers are renewing leases (or failing fast and retrying).
3. Restart workers to allow a fresh lease claim.

## Workflow execution fencing and migration

The optional `FencedWorkflowStore` capability gives each successful workflow
claim a fresh `executionId`. The runtime captures that opaque token with the
runner delivery and uses it for lease renewal, release, and failure recording.
A stale runner therefore cannot renew or release a newer lease, or finalize a
run after another execution has taken over. This is stronger than an
owner-only lease check: a new claim or explicit resume/rewind invalidates the
old execution identity.

Failure recording has two deliberately different modes:

- `terminal: false` records the error metadata only. The run status and lease
  remain unchanged so the worker's retry policy can decide whether to retry.
- Terminal failure records the error and transitions the run to failed, releasing
  its lease. This operation is applied only when the captured `executionId` is
  still current.

When a terminal-failure callback is recovered after a delivery interruption,
the runtime uses the trusted envelope and captured execution token persisted in
task status. A custom or legacy store that does not implement
`FencedWorkflowStore` cannot safely perform managed terminal failure; Stem logs
that limitation and does not use an unsafe owner-only fallback. Operators must
handle such failures with the store's own tooling or upgrade the store.

Managed terminalization requires the execution identity captured by the
failing delivery. A delivery that never acquired a claim cannot terminalize
another execution's run.

### Rolling upgrades

For SQL-backed stores, apply the package's new workflow execution-fencing
migration before enabling the new workers. SQLite adds `execution_id` to
`wf_runs`; PostgreSQL adds `execution_id` and its execution index to
`stem_workflow_runs`. Do not rely on stale-execution protection while old and
new workers share a store: old workers do not carry or enforce execution
identities. Drain or isolate old workers, apply the migration, then run the
fenced workers. Independently opened or reopened SQLite stores also generate
workflow run IDs as UUIDs, avoiding collisions between independent handles.

Execution fencing covers the claim lease operations and managed terminal-failure
finalization only. It does not condition every workflow write, provide
exactly-once execution, guarantee all writes are atomic, or make external
side effects safe. Use idempotency keys and application-level transactions for
those guarantees.

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
