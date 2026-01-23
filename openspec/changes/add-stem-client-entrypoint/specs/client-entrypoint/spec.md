## ADDED Requirements
### Requirement: StemClient Entry Point
The system SHALL provide a `StemClient` entrypoint that owns broker/backend/store configuration and runtime registries.

#### Scenario: Create a client for local execution
- **WHEN** a developer creates a `StemClient` with local configuration
- **THEN** the client provides access to task/workflow runtime wiring without passing broker/backend/store separately

### Requirement: Worker Construction from StemClient
The system SHALL allow workers to be created with a `StemClient` instance.

#### Scenario: Pass StemClient to worker
- **WHEN** a worker is created with a `StemClient`
- **THEN** the worker uses the client’s broker/backend/registries for execution

### Requirement: Workflow Runtime Construction from StemClient
The system SHALL allow workflow runtimes/apps to be created with a `StemClient` instance.

#### Scenario: Pass StemClient to workflow app
- **WHEN** a workflow app is created with a `StemClient`
- **THEN** the app uses the client’s broker/backend/store/event bus without separate wiring

### Requirement: Cloud-backed StemClient Implementation
The system SHALL provide a cloud-backed `StemClient` implementation that connects through the gateway.

#### Scenario: Cloud client initialization
- **WHEN** a developer creates a cloud `StemClient`
- **THEN** it configures the gateway-backed broker/backend/store implementations

### Requirement: Backwards Compatibility
The system SHALL preserve existing `StemApp` and `StemWorkflowApp` entrypoints.

#### Scenario: Existing bootstrapping continues to work
- **WHEN** an application uses existing app constructors
- **THEN** behavior remains unchanged
