# Design: Stem App Bootstrap Helpers

## Overview
We introduce two layered helpers that encapsulate the boilerplate required to
start a Stem runtime:

- `StemApp`: core helper responsible for building a `Stem` instance, managing a
  `Worker`, and exposing lifecycle hooks. It relies on pluggable factory objects
  to construct brokers, result backends, revoke stores, etc.
- `StemWorkflowApp`: builds on `StemApp` to configure a `WorkflowRuntime` and
  selected `WorkflowStore`, registering workflows and providing high-level
  operations (`startWorkflow`, `waitForCompletion`, `shutdown`).

Adapters (Redis, Postgres, SQLite) implement extension getters/functions that
produce the factory instances consumed by these helpers without hard-coding
adapter knowledge inside the core package.

## Components

### Core Factories
- `StemBrokerFactory`: wraps an async builder returning a `Broker`.
- `StemBackendFactory`: wraps an async builder returning a `ResultBackend`.
- `WorkflowStoreFactory`: async builder returning a `WorkflowStore`.
- Additional optional factories (rate limiter, revoke store, unique task
  coordinator) use the same shape and default to in-memory implementations.

Factories expose convenience constructors for in-memory defaults so the core
package keeps working without adapters.

### StemApp Lifecycle
- Accepts handler registrations (`TaskHandler` instances or registries) and
  factory instances.
- `StemApp.startWorkers()` spins up one or more workers; `shutdown()` disposes
  worker(s), backend, broker, stores.
- Exposes `stem`, `worker`, `registry`, and `config` getters to allow advanced
  customisation (e.g. adding middleware before start).

### StemWorkflowApp
- Accepts `StemApp` factories plus workflow definitions.
- On `start()`, registers workflow handlers and optionally starts workers if
  not already running.
- Provides methods: `startWorkflow`, `runWorkflow` (fire-and-wait), `getRun`
  (inspect stored state), and `shutdown` (delegates to inner app and closes
  workflow store).

### Adapter Extensions
Each adapter package adds extension methods returning the appropriate factory:

```dart
extension StemRedisFactories on StemBrokerFactory {
  static StemBrokerFactory redis(String uri, {TlsConfig? tls});
}

extension RedisWorkflowStoreFactory on WorkflowStoreFactory {
  static WorkflowStoreFactory redis(String uri, {String namespace = 'stem'});
}
```

This keeps the core helper decoupled from adapter implementations.

## Alternatives Considered
- **Static global singletons:** rejected to avoid shared state across tests and
  to keep configuration explicit.
- **CLI-only bootstrap:** out of scope; we want reusable code helpers for
  application and test environments.

## Open Questions
- Should `StemApp` manage multiple workers/queues out of the box? Initial
  version keeps a single worker with configurable concurrency; future change can
  add clustering if needed.
- Do we provide synchronous convenience (`runWorkflowAndWait`) that polls the
  result backend? For now, we surface a simple wait that leverages the
  workflow store `get`/`watch` functionality; more sophisticated APIs can land
  later.
