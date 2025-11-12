# Proposal: Make Chord Callbacks Fault-Tolerant

## Background
Stem’s Canvas implements chords by polling the result backend from the calling
process (`Canvas._monitorChord`). The callback is dispatched only while that
poller remains alive. If the originating process exits, crashes, or loses
connectivity, the chord never fires even though every body task may have
succeeded. This breaks parity with Celery/Sidekiq expectations and violates the
“fire-and-forget” nature of background orchestration.

## Problem
- Chord completion depends on an in-process loop; a crashed producer aborts the
  callback permanently.
- No other component (workers, backend) steps in to enqueue the callback when
  the group finishes.
- Operators cannot rely on chords for long-running workflows or when API
  servers scale down quickly.

## Goals
- Ensure chord callbacks are enqueued exactly once once every body task reaches
  a terminal state, regardless of producer liveness.
- Provide resilience across worker restarts by making chord completion driven
  by durable state (result backend or control plane).
- Emit observability signals so operators can trace chord lifecycle events.

## Non-Goals
- Redesigning chain/group semantics beyond the callback reliability fix.
- Guaranteeing callback execution if the callback task itself fails (handled by
  normal retries).
- Introducing a separate chord microservice in this iteration.

## Proposed Approach
- Move chord monitoring into a worker-side coordinator that watches group
  progress via the result backend’s `watch`/`getGroup` APIs. When the expected
  results arrive, the coordinator enqueues the callback task.
- Persist chord state (e.g. completion flag) in the backend to avoid double
  enqueue by multiple workers; use an atomic compare-and-set or distributed lock
  to ensure a single callback dispatch.
- Update Canvas to register chords with the coordinator instead of launching its
  own monitoring loop, maintaining API compatibility for producers.

## Risks & Mitigations
- **Double callback**: Without atomic updates, two coordinators could enqueue
  the callback. Mitigate with backend-supported compare/update or dedicated
  lock keyed by chord id.
- **Backend polling cost**: Coordinators should back off intelligently or rely
  on streaming `watch` APIs to reduce load.
- **Compatibility**: Canvas should still return a future resolving to the
  callback task id; we’ll convert it into a backend “wait” that observes the
  coordinator’s confirmation.

## Validation
- Unit tests covering coordinator behaviour and double-enqueue prevention.
- Integration test simulating producer shutdown before completion to ensure the
  callback still fires.
- Documentation updates explaining the new reliability guarantees.
