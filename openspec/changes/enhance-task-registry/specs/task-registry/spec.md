## ADDED Requirements

### Requirement: Registry detects duplicate registrations
Stem MUST reject duplicate task registrations unless the caller explicitly opts to override the existing handler.
#### Scenario: Handler registered twice without override
- Given `SimpleTaskRegistry`
- And a handler named `sample.task`
- When the handler is registered
- And the same handler is registered again without requesting an override
- Then the registry throws an `ArgumentError` explaining the duplicate

#### Scenario: Handler registered twice with override
- Given `SimpleTaskRegistry`
- And an original handler named `sample.task`
- And a replacement handler with the same name
- When the original is registered
- And the replacement is registered with `overrideExisting: true`
- Then the replacement is stored
- And calling `resolve('sample.task')` returns the replacement handler

### Requirement: Registry exposes metadata and enumeration
Stem MUST expose read-only access to the registered handlers and provide metadata for each entry.
#### Scenario: Listing registered handlers
- Given `SimpleTaskRegistry`
- And two handlers are registered
- When `handlers` is accessed
- Then it returns both handlers without allowing mutation

#### Scenario: Handler metadata default
- Given any `TaskHandler`
- When `metadata` is read without overriding
- Then it returns an empty metadata object with no tags or description

### Requirement: Typed task definitions streamline enqueue calls
Stem MUST offer typed task definitions that encode arguments consistently and integrate with the `Stem.enqueueCall` helper.
#### Scenario: Building a task definition with args encoder
- Given a `TaskDefinition` with a custom encoder
- When it is invoked with typed arguments
- Then the produced `TaskCall` encodes arguments into a map using the encoder

#### Scenario: Enqueueing via typed call
- Given a `Stem` instance and a registered handler
- And a `TaskDefinition` for that handler
- When `Stem.enqueueCall` is invoked with the definition
- Then it emits the same envelope as the raw `enqueue` API
- And it returns the generated envelope id
