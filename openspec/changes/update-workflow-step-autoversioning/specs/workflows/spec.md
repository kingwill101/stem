## MODIFIED Requirements

### Requirement: Auto-versioned workflow steps
Workflow steps MUST support an opt-in `autoVersion` mode so the runtime can
execute the same logical step multiple times, storing checkpoints with
sequential suffixes and resuming from the correct iteration after suspensions or
failures. The workflow stores MUST treat suffixed checkpoints as belonging to
their logical base step when computing cursors, rewinding, or emitting run
metadata so that auto-versioned loops behave the same across adapters.

#### Scenario: WorkflowStore rewind resets versioned checkpoints
- **GIVEN** a workflow run has stored checkpoints `repeat#0`, `repeat#1`, and
  `tail`
- **WHEN** `WorkflowStore.rewindToStep(runId, 'repeat')` executes
- **THEN** the store MUST delete every checkpoint for `repeat` (all `repeat#*`)
  and any later steps
- **AND** the run MUST transition to `suspended` with `suspensionData.step ==
  'repeat'`, `suspensionData.iteration == 0`, and `suspensionData.iterationStep
  == 'repeat'`
- **AND** `RunState.cursor` MUST equal the base index of `repeat` so the runtime
  restarts the step from iteration zero.

#### Scenario: Cursor counts logical steps despite suffixed checkpoints
- **GIVEN** a versioned step produced checkpoints `poll#0`, `poll#1`, and
  `poll#2`
- **WHEN** `WorkflowStore.get` or `WorkflowStore.listRuns` returns the run state
- **THEN** `cursor` MUST report the number of logical steps completed (for the
  example above, `1`) rather than the number of individual suffixed checkpoints
- **AND** clearing the versioned checkpoints via `rewindToStep` MUST reset the
  cursor to the target step index.

#### Scenario: listSteps returns versioned checkpoints in execution order
- **GIVEN** a workflow run stored checkpoints `poll#0`, `poll#1`, followed by
  `finalize`
- **WHEN** `WorkflowStore.listSteps` is invoked
- **THEN** the entries MUST include each suffixed checkpoint in execution order
  with their stored values so the runtime can hydrate the latest iteration.
