## ADDED Requirements

### Requirement: Application bootstrap helpers
Stem MUST provide factory-driven helpers that construct a minimal Stem runtime with sensible defaults and allow adapters to contribute driver-specific factories.

#### Scenario: Create in-memory Stem app
- **GIVEN** a developer calls `await StemApp.inMemory(tasks: [handler])`
- **WHEN** `startWorkers()` is invoked
- **THEN** the helper MUST register the provided handler, start a worker using the in-memory broker/backend, and expose the underlying `Stem` instance for enqueueing tasks
- **AND** `shutdown()` MUST dispose the worker, broker, and backend without throwing.

#### Scenario: Extend app with adapter factory
- **GIVEN** an adapter package exports `StemBrokerFactory.redis`
- **WHEN** a developer passes `broker: StemBrokerFactory.redis('redis://local')` into `StemApp.create`
- **THEN** the helper MUST use the Redis broker instance instead of the in-memory broker while preserving the same lifecycle semantics.

### Requirement: Workflow bootstrap helper
Stem MUST ship a `StemWorkflowApp` wrapper that builds on the application helper to manage `WorkflowRuntime` setups with pluggable workflow stores.

#### Scenario: Run workflow via helper
- **GIVEN** a developer creates `StemWorkflowApp.inMemory(workflows: [flow])`
- **WHEN** they call `await app.startWorkflow('demo.workflow')`
- **THEN** the workflow MUST execute using the configured store and runtime without additional boilerplate
- **AND** `await app.shutdown()` MUST release the workflow store, worker, and broker resources.
