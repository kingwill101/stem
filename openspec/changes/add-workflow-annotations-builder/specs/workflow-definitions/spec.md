## ADDED Requirements
### Requirement: Annotated Workflow Definitions
The system SHALL allow developers to define workflows using annotations on classes and methods.

#### Scenario: Class-based workflow definition
- **WHEN** a class is annotated with `@workflow.defn` and its `run` method is annotated with `@workflow.run`
- **THEN** the workflow is eligible for registration and execution via the generated registry

### Requirement: Annotated Workflow Steps
The system SHALL allow individual workflow steps to be declared with a dedicated annotation.

#### Scenario: Step annotation
- **WHEN** a method is annotated with `@workflow.step`
- **THEN** the generated registry exposes that step as an invocable definition

### Requirement: Build-Time Registry Generation
The system SHALL generate a registry of annotated workflows, steps, and tasks at build time.

#### Scenario: Registry generation
- **WHEN** `build_runner` is executed for a package that uses Stem annotations
- **THEN** a registry entrypoint is generated that registers all annotated definitions

### Requirement: Explicit Registry Loading
The system SHALL require an explicit runtime call to load generated definitions.

#### Scenario: Opt-in registration
- **WHEN** the application calls `registerStemDefinitions(registry)` from the generated file
- **THEN** the annotated workflows and steps are available for execution

### Requirement: Stable Definition Identifiers
The system SHALL provide a stable identifier for workflows and steps, with an optional explicit override.

#### Scenario: Custom identifier override
- **WHEN** a workflow or step annotation provides an explicit name
- **THEN** that name is used as the definition identifier instead of the default class/method name
