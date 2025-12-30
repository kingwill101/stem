# Design: Durable workflow event watchers

## Overview
We introduce explicit watcher records to coordinate `awaitEvent`/`emit`. Each store will manage a per-topic watcher registry that links run IDs, step names, deadlines, and payloads. Emission becomes a transactional operation that writes the payload, marks watchers as satisfied, and re-queues the run.

## Runtime Changes
- `FlowContext.awaitEvent` attaches metadata (`topic`, optional deadline). The runtime stores a watcher via new store APIs when suspending.
- Upon resume, the runtime reads watcher payload data. If the payload is present, it injects it into `resumeData` and removes the watcher; otherwise, suspension persists the watcher until an event arrives or a timeout fires.
- `emit` delegates to the store, which atomically records payloads and returns affected run IDs to enqueue.

## Store Contract Extensions
Add methods such as:
- `registerWatcher(runId, stepName, topic, deadline)`
- `resolveWatcher(topic, payload)` returning run IDs + payloads
- `listWatchers(topic, limit)` for inspection

Implementations:
- **In-memory** – Model watchers as maps of topic -> list of watcher records; support deadlines via existing due queue.
- **Redis** – Use hash sets and sorted sets (topic hash storing payload, watcher list storing run IDs). A Lua script ensures atomic payload persistence and run requeue.
- **Postgres** – Add tables `wf_watchers` and `wf_events` with the necessary columns; extend existing SQL to manage watchers transactionally.
- **SQLite** – Similar tables to Postgres with indices on topic and deadlines.

## Failure Semantics
- Emission after timeout should do nothing (watchers already cleaned up by due runs).
- Repeated emission updates payload but only resumes runs once; subsequent runs ignore identical payloads.
- If a worker crashes after resuming but before checkpointing, the watcher remains removed and the payload remains accessible via the checkpoint entry saved in `markResumed` to avoid re-delivery.

## Risks & Mitigations
- **Complex store migrations** – Postgres/SQLite require schema updates; migrations will be included with tests.
- **Redis consistency** – Lua script ensures emission updates are atomic.
- **Performance** – Watcher tables are indexed by topic and deadlines; we keep operations O(log n) per watcher.
