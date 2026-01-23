## Context
The workflow UI needs stable, queryable metadata to show definitions, step graphs, and step-level history. Stem currently exposes workflow runtime state but does not persist workflow definitions or per-step execution events.

## Goals / Non-Goals
- Goals:
  - Provide a core registry for workflow definitions and step metadata.
  - Provide a runtime sink for step execution events.
  - Keep metadata inside the workflow layer (not ResultBackend).
  - Provide default in-memory/no-op implementations for local development.
- Non-Goals:
  - Gateway APIs and persistence are out of scope for this change.
  - No changes to ResultBackend schemas.

## Decisions
- Introduce `WorkflowRegistry` for definition metadata and `WorkflowIntrospectionSink` for runtime events.
- Emit registry entries from `StemWorkflowApp` at boot.
- Emit step-level events from the workflow runtime (start/complete/fail/retry).

## Risks / Trade-offs
- Additional runtime overhead from event emission.
  - Mitigation: default sink is no-op; implementations can batch or throttle.
- Need to ensure definition metadata stays consistent with runtime.
  - Mitigation: definitions are built from registered workflows on boot.

## Migration Plan
- Add interfaces and defaults in core.
- Hook into workflow app initialization and step execution paths.
- Gateway integration is a follow-up change.

## Open Questions
- Do we need a registry version/hash strategy beyond semantic version?
- Should step events include input/output payload sizes by default?
