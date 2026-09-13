---
title: How It Works
---

Stem workflows are built on top of the regular Stem queue runtime, but they are
not just “tasks that sleep”. They add a workflow store, durable suspension
state, checkpoint/journal data, and orchestration-specific runtime metadata.

## Runtime components

`StemWorkflowApp` bundles:

- `runtime`: workflow registration plus run execution/resume coordination once
  the internal workflow task is invoked
- `store`: persisted runs, checkpoints, watchers, due runs, and results
- `eventBus`: topic-based resume channel
- `app`: the underlying `StemApp` with broker, backend, and worker

## Internal execution task

Each workflow run is executed by an internal task named `stem.workflow.run`.
That task is delivered on the orchestration queue, claimed by a worker, and
then delegated into the workflow runtime. A sleep or event wait persists its
continuation before returning control to the worker; resumption is a new
delivery, not a kept-alive invocation.

This is why workflow logs show task lifecycle lines alongside workflow runtime
lines.

## State model

Stem keeps materialized workflow state in the workflow store:

- run metadata and status
- flow step results and script checkpoint results
- suspension records
- due-run schedules
- topic watchers
- runtime metadata such as queue and serialization info

That model is simpler to query from dashboards and store adapters, while still
allowing durable resume and recovery. On replay, the runtime reads completed
checkpoints/journal entries and advances from the first unfinished boundary.
User code outside those boundaries can run again.

## Manifests

`WorkflowRuntime.workflowManifest()` exposes typed manifest entries for all
registered workflows.

The manifest now distinguishes:

- flow `steps`
- script `checkpoints`

That distinction is reflected in the dashboard and generated metadata so script
workflows no longer look like they are driven by a declared step list.

## Leases and recovery

Workflow runs are lease-based.

- a worker claims a run for a finite lease duration
- the lease is renewed while the run is active
- another worker can take over after lease expiry if the first worker crashes

Operational guidance:

- renew leases before expiry when the store supports renewal
- keep clocks in sync across workers
- make checkpoint side effects idempotent: delivery and retry are at least once

When a lease expires, another worker may take over. Fencing prevents the stale
owner from committing a later state transition, but it cannot undo an external
side effect that happened before the crash.
