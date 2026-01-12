## ADDED Requirements

### Requirement: Workflow definitions are captured in a registry
The system SHALL capture workflow definitions (name, version, steps, edges, metadata) in a workflow registry when a `StemWorkflowApp` boots.

#### Scenario: Workflow registry is populated on boot
- **WHEN** a `StemWorkflowApp` starts with registered workflows
- **THEN** the workflow registry contains entries for each registered workflow definition

### Requirement: Workflow definitions include step metadata
Workflow definitions SHALL include step identifiers, titles, kinds, and associated task names to support step-level introspection.

#### Scenario: Step metadata is available for UI usage
- **WHEN** a workflow definition is retrieved from the registry
- **THEN** each step includes its identifier, title, kind, and task name list

### Requirement: Workflow runtime emits step execution events
The workflow runtime SHALL emit step-level execution events (started, completed, failed, retrying) to a workflow introspection sink.

#### Scenario: Step execution events are emitted
- **WHEN** a workflow step starts and completes
- **THEN** the introspection sink receives corresponding step events with timestamps and run identifiers

### Requirement: Default implementations do not require persistence
The system SHALL provide a default in-memory workflow registry and a no-op introspection sink so local runs work without external dependencies.

#### Scenario: Default implementations are available
- **WHEN** the workflow system is initialized without custom registry or sink
- **THEN** in-memory registry and no-op sink are used by default
