## ADDED Requirements

### Requirement: Task registry captures task definitions
The system SHALL capture task definitions (name, description, tags, idempotency flag, attributes) in a task registry for tooling and UI usage.

#### Scenario: Task registry is populated on boot
- **WHEN** a `StemApp` starts with registered tasks
- **THEN** the task registry contains entries for each registered task definition

### Requirement: Task definition payload fields
Task definition payloads SHALL include the following fields:
- `name` (string)
- `description` (string, nullable)
- `tags` (string list)
- `idempotent` (bool)
- `attributes` (map of string → JSON-serializable value)

#### Scenario: Task definition payload is serialized
- **GIVEN** a task is registered with description, tags, idempotency flag, and attributes
- **WHEN** the task definition is serialized for registry sync
- **THEN** the payload includes the required fields with their current values

### Requirement: Cloud gateways can persist task definitions
When running in Stem Cloud mode, the system SHALL support syncing task definitions from a local task registry to a gateway-backed registry so that the gateway can persist and serve task metadata for UI and API consumers.

#### Scenario: Definitions are synced on boot in cloud mode
- **GIVEN** a `StemApp` is configured to use a gateway-backed task registry sync
- **WHEN** the app boots with registered tasks
- **THEN** the gateway receives the task definitions and persists them for later queries

#### Scenario: Definitions are synced on task registration
- **GIVEN** the gateway sync registry is enabled
- **WHEN** a task is registered at runtime
- **THEN** the gateway is synchronized with the new definition

### Requirement: Gateway exposes stored task definitions
The gateway SHALL expose stored task definitions to clients so dashboards can describe tasks without direct access to worker code.

#### Scenario: Gateway returns stored task definitions
- **GIVEN** the gateway has persisted task definitions
- **WHEN** clients request task metadata
- **THEN** the response includes the stored task definition fields

### Requirement: Local registries remain configurable
The system SHALL allow users to provide a local `TaskRegistry` implementation even when syncing to the gateway, so users can extend or cache registry behavior while still enabling cloud persistence.

#### Scenario: Registry composition in cloud mode
- **GIVEN** a user provides a custom `TaskRegistry`
- **AND** a gateway sync registry is enabled
- **WHEN** a task is registered
- **THEN** the local registry is updated
- **AND** the gateway is synchronized with the same definition
