# Design: Workflow cancellation policies

## Overview
We add optional cancellation parameters to `WorkflowRuntime.startWorkflow` (and helper APIs) capturing:
- `maxRunDuration` – overall wall-clock limit from start to completion.
- `maxSuspendDuration` – maximum time a single suspension may last before auto-cancel.
- Optional `reason` metadata for operator display.

## Runtime Behaviour
- `createRun` stores policy metadata alongside the run (new fields or JSON column).
- A new periodic check (reusing the existing timer loop) evaluates runs:
  - If `maxRunDuration` exceeded, transition to cancelled.
  - If `resumeAt` exists and `maxSuspendDuration` would be exceeded at the next tick, cancel instead of re-queueing.
- Cancellation emits signals with metadata specifying which limit triggered the action.

## Store Changes
- Stores persist cancellation policy metadata (in JSON or dedicated columns) and expose them via `RunState`.
- `markRunning`, `suspendUntil`, etc., update the last-seen timestamps so the runtime can compute elapsed durations.

## Operator Visibility
- CLI `stem wf show` displays policy metadata and whether auto-cancel triggered.
- Signals propagate cancellation reason for observability.

## Risks
- Schema changes for Postgres/SQLite; we use migrations with defaults to maintain compatibility.
- Need to ensure manual cancellations still work and override policy logic.
