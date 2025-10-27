## ADDED Requirements

### Requirement: Fluent builder constructs enqueue requests
Stem MUST expose a builder API that allows callers to set headers, options, metadata, and schedule details before producing a `TaskCall` or enqueuing directly.

#### Scenario: Build TaskCall via builder
- Given a `TaskDefinition`
- When a developer uses the builder to set headers, priority, and meta
- Then calling `build()` returns a `TaskCall` reflecting those values

#### Scenario: Direct enqueue using builder
- Given a `Stem` instance and a `TaskDefinition`
- When `enqueue()` is called on the builder
- Then the task is enqueued and the builder returns the task id

### Requirement: Registry emits events on registration
The default task registry MUST emit events when handlers are registered or overridden.

#### Scenario: Handler registration event
- Given `SimpleTaskRegistry`
- And a listener subscribed to `onRegister`
- When `register` is invoked
- Then the listener receives the handler and name

### Requirement: CLI lists tasks with metadata
The Stem CLI MUST provide a command that lists registered tasks with descriptions, tags, and idempotency flags.

#### Scenario: Human-readable listing
- Given `stem tasks ls`
- When run without flags
- Then it prints a table showing task name, description, tags, and idempotency

#### Scenario: JSON output
- Given `stem tasks ls --json`
- When executed
- Then it emits structured JSON containing the same metadata

### Requirement: Tracing includes task metadata
Producer spans created by `Stem.enqueue` MUST include handler metadata attributes when available.

#### Scenario: Span contains metadata attributes
- Given a handler with metadata
- When `Stem.enqueue` is invoked
- Then the span attributes contain description, idempotent flag, and tags
