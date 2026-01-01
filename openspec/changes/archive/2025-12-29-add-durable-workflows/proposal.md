# Proposal: Add Durable Workflow Engine

## Background
Stem customers want to orchestrate long-running, event-driven workflows with the
same reliability guarantees across Redis, Postgres, and SQLite deployments. Our
current Canvas primitives (chain, group, chord) cover fan-out/fan-in but do not
persist execution checkpoints, handle suspensions, or resume based on timers and
external events. Partners already model these patterns on top of Stem and need
a first-class, portable DX to reduce bespoke infrastructure.

## Problem
- There is no durable workflow abstraction that checkpoints steps, suspends, and
  resumes reliably after crashes or redeploys.
- Each backend (Redis, Postgres, SQLite) would require bespoke logic; teams
  currently have no shared engine or interfaces to target.
- Operators lack CLI tooling to inspect, resume, cancel, or emit workflow
  events.

## Goals
- Introduce a first-class workflow layer inside the core `stem` package that
  exposes a uniform API (`Workflow`, `Flow.step`, `Flow.awaitEvent`,
  `Flow.sleep`) backed by backend-agnostic `WorkflowStore` and `EventBus`
  contracts.
- Deliver production-ready store implementations for Redis, Postgres, and
  SQLite that satisfy the same behavioural contracts (checkpoint idempotency,
  suspensions, timers).
- Add operational tooling (CLI commands) so developers can start workflows,
  list runs, inspect state, emit events, and cancel/rewind runs.

## Non-Goals
- Building a graphical dashboard in this iteration (we will expose CLI hooks
  and leave UI work for a later change).
- Providing exactly-once execution; the engine will continue to rely on
  at-least-once semantics with idempotent steps.
- Supporting exotic backends beyond Redis, Postgres, and SQLite in v1.

## Proposed Approach
1. Define backend-agnostic interfaces (`WorkflowStore`, `EventBus`) covering run
   creation, step checkpoints, suspensions (timer or topic), and state
   transitions within `packages/stem`.
2. Implement concrete stores/buses in the existing adapter packages:
   - `stem_redis`: hashes/zsets/sets with Lua scripts for atomic checkpoints and
     timer coordination.
   - `stem_postgres`: SQL tables (`wf_runs`, `wf_steps`) with transactional
     updates and `LISTEN/NOTIFY` for topic fan-out.
   - `stem_sqlite`: same schema using WAL mode and polling loops for
     timers/topics.
3. Create an internal `workflow.run` handler that resumes runs by reading the
   cursor, executing steps through the Flow API, suspending when required, and
   using existing Stem lease/heartbeat mechanics.
4. Ship a new CLI group (`stem wf`) with subcommands to start, list, show,
   cancel, rewind, and emit workflow events.
5. Document usage patterns, backend configuration, and safety guidance.

## Risks & Mitigations
- **Different backend semantics:** Provide detailed integration tests and
  contract suites per implementation to ensure consistent behaviour.
- **Polling overhead (SQLite/Postgres timers):** Use efficient `LIMIT` queries,
  `SKIP LOCKED`, and backoff to minimise load.
- **Double resume:** Rely on atomic updates/locks (Lua scripts, SQL transactions
  with `FOR UPDATE`, or single-writer loops) to ensure only one resume at a time
  for a given run.

## Validation
- Contract tests for `WorkflowStore`/`EventBus` implementations across all three
  backends.
- End-to-end workflow tests covering step checkpointing, timer suspension,
  event-driven resumes, failure/retry behaviour, and cancellation/rewind.
- CLI integration tests to ensure operational flows work as expected.
