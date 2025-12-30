# Proposal: Add Stem App Bootstrap Helpers

## Background
Developers currently wire brokers, result backends, workflow stores, registries,
and workers manually for every quick start. Even the simplest workflow example
requires dozens of lines of setup and teardown logic, which makes the DX feel
heavy and error prone.

## Problem
- No unified factory exists to provision a Stem runtime with sensible defaults.
- Workflow examples and tests must repeat boilerplate to create brokers,
  backends, workflow stores, registries, runtimes, and workers.
- Adapter packages cannot contribute store/broker conveniences because there is
  no shared extension point.

## Goals
- Introduce a `StemApp` helper in the core package that builds Stem + workers
  from configurable factories (in-memory by default).
- Expose a `StemWorkflowApp` helper layered on top of `StemApp` to manage
  `WorkflowRuntime` and `WorkflowStore` creation.
- Allow adapter packages (stem_redis, stem_postgres, stem_sqlite, …) to supply
  convenience factories for their specific broker/backend/store types.

## Non-Goals
- Changing production configuration flows for existing apps; the helpers are
  opt-in convenience wrappers.
- Replacing low-level APIs (developers can still build Stem/Worker manually).
- Providing a GUI or CLI wizard for workflow setup (future work).

## Proposed Approach
1. Add abstract factory types (`StemBrokerFactory`, `StemBackendFactory`,
   `WorkflowStoreFactory`, etc.) to `package:stem` alongside an orchestrating
   `StemApp` class that can:
   - register handlers
   - construct `Stem`, `Worker`, and manage lifecycle
   - expose `stem`, `worker`, and `registry` getters for customisation
2. Build `StemWorkflowApp` in `package:stem` that wraps `StemApp`, wires a
   `WorkflowRuntime`, registers workflow handlers, and exposes high-level
   methods (`startWorkflow`, `waitFor`, `shutdown`).
3. Extend adapter packages to provide factory helpers
   (`StemBrokerFactory.redis`, `WorkflowStoreFactory.redis`, etc.) so
   applications can opt into specific backends by importing the adapter.
4. Update workflow example/tests to consume the new helpers; keep in-memory
   defaults for documentation.

## Risks & Mitigations
- **Factory explosion:** keep the initial surface small (broker, backend,
  workflow store) and document how adapters extend it.
- **Lifecycle confusion:** document shutdown behaviour and make helpers idempotent
  so repeated calls don’t throw.
- **Adapter coupling:** only expose extension APIs (no adapter-specific imports
  inside the core helper) to preserve modularity.

## Validation
- Unit tests covering in-memory `StemApp`/`StemWorkflowApp` creation and
  shutdown semantics.
- Integration tests that demonstrate adapter-provided factories (e.g. Redis,
  Postgres, SQLite) can build working workflow apps.
- Documentation updates (example + README snippet) showing the simplified DX.
