# Design: Workflow heartbeat on checkpoint save

## Overview
We treat the workflow run’s `updatedAt` field as a lightweight lease heartbeat.
Whenever a step persists progress via `WorkflowStore.saveStep`, the store updates
`updatedAt` to `NOW()` (or the equivalent) in the same transaction. This mirrors
Absurd’s behaviour where `set_task_checkpoint_state` refreshes the lease owner
at checkpoint time.

## Runtime changes
- Introduce a `heartbeatAt` timestamp in `RunState` (backed by `updated_at` in
  durable stores). The runtime keeps using `TaskContext.extendLease` for broker
  visibility while also relying on the store heartbeat when surfacing run
  details.
- After each successful `saveStep`, the runtime expects the store to return a
  `RunState` with a newer `updatedAt`. No additional RPC is required—the store
  performs the heartbeat internally.

## Store updates
- **Postgres / SQLite**: wrap `saveStep` inserts in a transaction that also
  updates `_runsTable.updated_at = NOW()`. Indices already exist on the column,
  so no schema change is required.
- **Redis**: add the ISO-8601 timestamp to the run hash (`updated_at`) while
  writing the checkpoint.
- **In-memory**: mutate the stored `RunState` with a fresh `updatedAt` when
  caching the checkpoint.

## Testing
- Adapter contract suite asserts that `updatedAt` increases after `saveStep`.
- Runtime test executes a workflow with multiple steps and checks the heartbeat
  timestamps advance between steps.
- README/example copy notes that checkpoints refresh the heartbeat so operators
  can reason about stale runs.
