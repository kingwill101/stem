# Proposal: Workflow run lease refresh on checkpoint save

## Problem
Workflow runs currently rely on the queue visibility timeout to retain
ownership while a worker is executing steps. The workflow stores do not record
heartbeat data when `saveStep` is invoked, so a long-running step leaves the run
state untouched until it suspends or completes. Operators and recovery tooling
have no durable signal that the run is still owned, and future ``later``
features that reclaim abandoned runs would misidentify active runs as stale.

## Goals
- Treat successful `saveStep` calls as a heartbeat that refreshes the run's
  lease/last-updated timestamp in every store implementation.
- Ensure the runtime writes the heartbeat consistently for Flow and script
  workflows without relying on adapter-specific behaviour.
- Update adapter tests so vendors implementing `WorkflowStore` get immediate
  feedback if they skip the heartbeat update.

## Non-Goals
- Building a full “run reclaimer” that reassigns abandoned runs.
- Changing queue visibility handling—the existing task `extendLease` calls stay
  in place.
- Reworking task-level heartbeat semantics outside the workflow subsystem.

## Measuring Success
- Contract tests assert that `saveStep` advances the run’s heartbeat/lease
  timestamp.
- Each adapter (In-memory, Redis, Postgres, SQLite) persists the refreshed
  timestamp atomically with the checkpoint write.
- Runtime integration test verifies the heartbeat is visible via
  `WorkflowStore.get` after `saveStep`.

## Rollout
- Implement heartbeat updates across stores, then land runtime + contract test
  changes in the same release so adapters remain in sync.
- Document the behaviour so third-party adapters adopt the same pattern.
