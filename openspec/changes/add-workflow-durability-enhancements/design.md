# Design: Workflow durability enhancements

## Overview
We strengthen the workflow runtime by carrying more responsibility inside the stores and the context helpers. The change touches three surfaces:
1. **Lease extension on checkpoint save** – `_WorkflowRunTaskHandler` already receives a `TaskContext`. We will thread this context into `WorkflowRuntime.executeRun` so the runtime can call `context.extendLease` whenever a checkpoint is written. This keeps the broker visibility timeout fresh without altering store contracts.
2. **Suspension metadata persistence** – When a step issues `sleep` or `awaitEvent`, the runtime will store normalized metadata (wake timestamp or event payload) via the `WorkflowStore`. Upon resume, it inspects `RunState.suspensionData` and skips scheduling a new suspension if the stored data indicates the condition is already satisfied.
3. **Idempotency helper** – We add a helper on `FlowContext` (and public documentation) that returns a stable string derived from the workflow run (`$workflowName/$runId/step`). Examples use it to integrate with external APIs.

## Key Decisions
- **Store contracts** – No signature changes required; stores already persist suspension data. We normalise the payload written by the runtime so every backend captures wake timestamps and emitted event payloads consistently.
- **Redis implementation** – No storage changes required; lease extension happens via the existing broker API from the workflow task handler.
- **Postgres/SQLite** – Same as Redis; stores simply persist suspension metadata.
- **Resume data** – Runtime reads persisted `resumeAt`/`waitTopic` plus `suspensionData` to avoid immediate re-suspension. This mirrors the guard pattern adopted from Absurd.
- **Helper exposure** – We avoid new classes; `FlowContext` gets `String idempotencyKey(String scope)` which concatenates run info and optional scope, ensuring developers can derive keys cheaply.

## Alternatives Considered
- **Dedicated heartbeat API** – Rejected; keeping lease refresh piggybacking on checkpoints avoids additional runtime calls and keeps semantics consistent with Absurd.
- **Global scheduler watchdog** – Out of scope; we rely on existing polling but tighten state transitions.
- **Decorator-based helpers** – Adding a separate helper type for idempotency was deemed overkill given `FlowContext` already exposes step metadata.

## Risks & Mitigations
- **Lease extension gaps** – Forgetting to thread `TaskContext` through the runtime would leave leases untouched; unit tests will assert that the handler calls `extendLease` when checkpoints commit.
- **Incomplete resume data** – Contract tests enforce that stores populate `suspensionData` so steps can rely on it.
- **Helper misuse** – Documentation updates and examples demonstrate using the idempotency helper to keep guidance consistent.
