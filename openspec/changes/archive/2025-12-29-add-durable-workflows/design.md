# Design: Durable Workflow Engine

## Overview
We surface workflow orchestration directly from the core `stem` package. Developers
write workflows using a lightweight `Workflow` / `Flow` API (`ctx.step`,
`ctx.awaitEvent`, `ctx.sleep`). The engine persists run state,
checkpoints, and suspensions through a pluggable `WorkflowStore` and resumes
execution by enqueuing a `workflow.run` task any time a suspension resolves. An
`EventBus` abstraction delivers external events into the store so suspended runs
waiting on a topic can resume.

## Core Interfaces
```dart
abstract class WorkflowStore {
  Future<String> createRun({required String workflow, required Map<String, dynamic> params, String? parentRunId, Duration? ttl});
  Future<RunState?> get(String runId);
  Future<T?> readStep<T>(String runId, String step);
  Future<void> saveStep<T>(String runId, String step, T value);
  Future<void> suspendUntil(String runId, DateTime when);
  Future<void> suspendOnTopic(String runId, String topic, {DateTime? deadline});
  Future<void> markRunning(String runId, {String? cursor});
  Future<void> markCompleted(String runId, dynamic result);
  Future<void> markFailed(String runId, Object error, StackTrace stack, {bool terminal = false});
  Future<void> markResumed(String runId);
  Future<List<String>> dueRuns(DateTime now, {int limit = 256});
  Future<List<String>> runsWaitingOn(String topic, {int limit = 256});
  Future<void> cancel(String runId);
  Future<void> rewindToStep(String runId, String step);
}

abstract class EventBus {
  Future<void> emit(String topic, Map<String, dynamic> payload);
  Future<int> fanout(String topic); // returns number of resumes triggered
}
```

The engine coordinates:
1. **Step execution**: reads checkpoints, executes step bodies, saves results.
2. **Suspension**: throws a sentinel when `awaitEvent` or `sleep` requests a
   pause; the worker acknowledges the original task so no duplicate processing
   occurs.
3. **Resumption**: backend-specific timer loops or event fan-out enqueue the
   `workflow.run` task for the suspended run id.

## Backend Implementations

### Redis (`stem_redis`)
- **Data structures**:
  - `stem:wf:run:<id>` hash storing status, cursor, params, result, wait_topic,
    resume_at, last_error, attempts.
  - `stem:wf:step:<id>` hash of checkpoints.
  - `stem:wf:timers` sorted set (`score = resume_at_ms`) for timer suspensions.
  - `stem:wf:suspended:topic:<topic>` set of run ids waiting on an event.
- **Atomics**:
  - Lua script for `saveStep` (`HSETNX`, set TTL, update cursor).
  - `suspendUntil`: `ZADD timers`, update run hash, optionally schedule TTL.
  - `suspendOnTopic`: `SADD` run id to topic set, mark run state.
- **Resumption**:
  - Timer mover loop fetches due entries (`ZRANGEBYSCORE`), enqueues resumes,
    and removes them.
  - `EventBus.emit` publishes to `stem:wf:topic:<topic>` and calls `fanout`
    which scans the set and enqueues resume tasks.

### Postgres (`stem_postgres`)
- **Schema**:
  ```sql
  create table wf_runs (
    id text primary key,
    workflow text not null,
    status text not null,
    cursor text,
    params jsonb not null,
    result jsonb,
    wait_topic text,
    resume_at timestamptz,
    last_error jsonb,
    attempts int not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );

  create table wf_steps (
    run_id text references wf_runs(id) on delete cascade,
    name text,
    value jsonb not null,
    primary key (run_id, name)
  );

  create index on wf_runs (resume_at) where resume_at is not null;
  create index on wf_runs (wait_topic) where wait_topic is not null;
  ```
- **Atomics**:
  - `saveStep`: transactional `insert ... on conflict do nothing`, update cursor
    in the same transaction (`select … for update`).
  - State transitions (`markRunning`, `markCompleted`, etc.) executed with
    row-level locks.
- **Event fan-out**:
  - `emit` uses `NOTIFY wf_topic_<topic>` with payload JSON.
  - A listener updates waiting runs (`update ... set status='running' ... returning id`) and enqueues resumes.
- **Timers**:
  - Poll `resume_at <= now()` using `select ... for update skip locked` to avoid
    race conditions, enqueue resumes, mark runs running/resumed.

### SQLite (`stem_sqlite`)
- **Schema**: mirrors Postgres using JSON stored as `TEXT`.
- **Configuration**: enable WAL mode, set `busy_timeout`.
- **Atomics**: use transactional `insert or ignore` for checkpoints.
- **Event/timer loops**: since SQLite lacks LISTEN/NOTIFY, background tasks poll
  `wait_topic` and `resume_at` tables with exponential backoff to enqueue resumes.

## Engine Execution Flow
1. `Workflow.start` calls `WorkflowStore.createRun`, enqueues `workflow.run`.
2. Worker executes `workflow.run`:
   - Calls `markRunning`, fetches `RunState`, and iterates steps starting from
     `cursor`.
   - For each step: if checkpoint exists via `readStep`, skip execution.
   - Otherwise execute body, call `saveStep`.
   - `awaitEvent` triggers `suspendOnTopic`; the worker cancels further progress
     and returns.
   - `sleep` triggers `suspendUntil`.
3. When suspension resolves, backend-specific loops enqueue the resume task.
4. On completion, `markCompleted` stores result and cleans up indexes.
5. On failure, `markFailed` records error; if non-terminal, the worker can retry
   based on Stem retry policy.

## CLI Extensions
- `stem wf start <name> <json>`: create run via Workflow API.
- `stem wf ls [--status|--workflow]`: list runs with pagination.
- `stem wf show <runId>`: display steps, cursor, errors, suspension details.
- `stem wf cancel <runId>` / `stem wf rewind <runId> <step>`: mutate run state.
- `stem emit <topic> <json>`: emit event into `EventBus`.

## Testing Strategy
- Contract test harness that exercises store/bus behaviours (checkpoint,
  suspend/resume, fan-out, cancellation) and runs against Redis, Postgres, and
  SQLite implementations.
- End-to-end workflow tests verifying:
  - Step idempotency (step executed once even after crash).
  - Timer resumes after delay with tolerance.
  - Event resume when `emit` is called.
  - Failure handling (terminal vs retryable).
- CLI integration tests using in-memory or fixture backends.

## Operational Considerations
- Timer/event background loops packaged as part of the workflow engine; they can
  run inside Beat or a new lightweight daemon.
- TTLs ensure completed runs eventually expire; defaults should be configurable.
- Observability: expose counters for run starts/completions, gauge of suspended
  runs, histograms for resume latency. Hook into Stem Signals and metrics.
