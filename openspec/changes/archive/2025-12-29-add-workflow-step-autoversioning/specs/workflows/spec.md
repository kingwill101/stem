## ADDED Requirements

### Requirement: Auto-versioned workflow steps
Workflow steps MUST support an opt-in `autoVersion` mode so the runtime can execute the same logical step multiple times, storing checkpoints with sequential suffixes and resuming from the correct iteration after suspensions or failures.

#### Scenario: Versioned step persists sequential checkpoints
- **GIVEN** a workflow step is declared with `autoVersion: true`
- **AND** the handler returns different values while looping through data
- **WHEN** the step executes three times in a single run
- **THEN** the workflow store MUST contain checkpoints named `step#0`, `step#1`, and `step#2`
- **AND** `FlowContext.iteration` MUST match the suffix for each execution.

#### Scenario: Versioned step resumes after suspension
- **GIVEN** a versioned step suspends on `ctx.awaitEvent(...)` during iteration `#2`
- **AND** the worker crashes after the suspension is recorded
- **WHEN** the run resumes after the event is emitted
- **THEN** the runtime MUST re-enter the handler with `FlowContext.iteration == 2`
- **AND** once the handler completes, the runtime MUST advance to iteration `#3` (or the next base step) without re-playing iterations `#0` or `#1`.

#### Scenario: Non-versioned steps retain single execution behaviour
- **GIVEN** an existing workflow step does not set `autoVersion`
- **WHEN** the step completes successfully
- **THEN** the runtime MUST continue to skip it on subsequent resumes, maintaining the current single-checkpoint semantics.
