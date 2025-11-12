## ADDED Requirements

### Requirement: Workflow SDK facade with step/await/sleep helpers
Stem MUST provide an additive workflow facade that wraps `FlowBuilder` so
developers can author workflows as a single async function that calls `step`,
`sleep`, and `awaitEvent` helpers with durability semantics identical to the
existing API. The facade MUST support auto-versioned steps and expose the same
resume data that `FlowContext` offers today.

#### Scenario: Facade `step` helper persists and replays results
- **GIVEN** a workflow is defined via the facade
- **WHEN** the script calls `await ctx.step('charge', () async => amount)`
- **THEN** the runtime MUST persist the returned value in the workflow store
  using the same checkpoint semantics as `FlowBuilder.step`
- **AND** subsequent replays MUST return the persisted value without
  re-invoking the callback.

#### Scenario: Facade exposes sleep/event helpers with replay safety
- **GIVEN** a facade-defined workflow calls `await ctx.sleep(Duration)`
  followed by logic that inspects `ctx.resumeData`
- **WHEN** the run resumes after the delay or an awaited event fires
- **THEN** the facade MUST re-enter the same async function with the resume
  payload available and MUST NOT schedule duplicate sleeps or events unless the
  handler explicitly requests it.

#### Scenario: Auto-versioned iterations surface via facade
- **GIVEN** a facade workflow marks a helper as versioned (e.g.
  `ctx.step('poll', autoVersion: true, ...)`)
- **WHEN** the workflow iterates three times
- **THEN** the workflow store MUST contain checkpoints `poll#0`, `poll#1`,
  `poll#2` and `ctx.iteration` (or equivalent) MUST match the current suffix on
  each replay.

#### Scenario: Shared adapter tests cover the facade
- **GIVEN** the shared adapter test package (`packages/stem_adapter_tests`)
- **WHEN** the facade ships
- **THEN** the contract suite MUST include coverage that exercises the facade
  against in-memory, Redis, Postgres, and SQLite stores so adapter behavior
  stays in lock-step.
