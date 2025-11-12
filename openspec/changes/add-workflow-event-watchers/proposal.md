# Proposal: Race-free workflow event watchers

## Problem
`ctx.awaitEvent` currently relies on polling and best-effort suspension metadata. In high-concurrency scenarios this leaves the following gaps:
- Event payloads can be lost if an event arrives between a workflow resuming and the worker failing before checkpointing the payload.
- Wait registrations (topic lists / due runs) are spread across stores without atomic association of payload + resume, making it hard to reason about delivery guarantees and eventual clean-up.
- Operators lack visibility into which runs are awaiting a topic and whether payloads have been captured already.

## Goals
- Introduce a durable tracking mechanism (watcher records) so awaiting runs resume exactly once with the payload that triggered them.
- Ensure event emission atomically records the payload, marks the watcher, and re-queues the run without races.
- Provide an inspection surface (store API + CLI follow-up change) that lists watchers per topic.

## Non-Goals
- Changing the existing `ctx.awaitEvent` developer API beyond semantics.
- Introducing push-based delivery; we remain pull-based but make state transitions durable.
- Providing UI tooling (covered in later changes).

## Measuring Success
- Contract tests validate that emitting an event during downtime still resumes the run with the original payload once the worker restarts.
- Dead-letter-like flows confirm that multiple event emissions do not resume the same run multiple times.
- Store implementations (memory/Redis/Postgres/SQLite) expose watcher inspection and cleanup primitives.

## Rollout
- Implement the new watcher persistence and atomic event handling across stores in one release.
- Update runtime + documentation simultaneously since semantics change.
