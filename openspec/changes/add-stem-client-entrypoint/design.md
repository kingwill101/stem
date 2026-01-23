## Context
Current Stem bootstrapping requires passing broker/backend/store/config to multiple places (workers, workflow runtime). The desired UX is a single entrypoint (`StemClient`) passed into workers and other components, similar to Temporal’s Client + Worker pattern.

## Goals / Non-Goals
- Goals:
  - Introduce `StemClient` as a single entrypoint for configuration and runtime access.
  - Allow workers and workflow runtimes to be created from or passed a `StemClient`.
  - Support default/local configuration and cloud-backed configuration without duplicating setup.
- Non-Goals:
  - No behavioral changes to task/workflow execution semantics.
  - No breaking removal of existing `StemApp`/`StemWorkflowApp` constructors.

## Decisions
- Decision: Add `StemClient` interface with factories for default/local and cloud-backed usage.
- Decision: Implement adapters so `StemWorker` and `StemWorkflowApp` can accept a `StemClient` directly (or can be created from it).
- Decision: Keep existing APIs but provide new `StemClient`-based overloads to preserve backwards compatibility.

## Risks / Trade-offs
- Additional abstraction layer; keep API surface minimal and document ownership/lifecycle.
- Cloud implementation must not leak gateway details into core APIs.

## Migration Plan
1. Add `StemClient` interface and default implementation.
2. Add cloud-backed client implementation.
3. Add worker/workflow constructors or factories that accept `StemClient`.
4. Update examples and docs to use `StemClient`.

## Open Questions
- Exact naming for factories (`StemClient.connect`, `StemClient.local`, etc.).
- Whether `StemApp`/`StemWorkflowApp` should be thin wrappers around `StemClient`.
