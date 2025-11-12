# Proposal: Update workflow step auto-versioning contract

## Problem
Auto-versioned workflow steps now exist, but the stores and runtime still lack a
precise contract for how suffixed checkpoints behave when runs rewind or resume.
Without that guardrail we have adapters that leave stale `step#iteration`
checkpoints behind, fail to reset the run cursor, or omit the iteration metadata
that the runtime expects after a suspension. This leads to loops hanging in the
same step, mismatched cursor values across adapters, and no high-level signal
when contract regressions occur.

## Goals
- Document how `WorkflowStore.rewindToStep` must treat versioned checkpoints:
  drop all suffixed entries for the target step, reset the cursor, and persist
  `suspensionData.iteration`.
- Ensure `WorkflowStore.get`/`listSteps` normalise checkpoint names so the
  cursor reflects logical step order and versioned entries stay in execution
  order.
- Add adapter contract tests that exercise versioned workflows against every
  store so all implementations surface identical semantics.

## Non-Goals
- Changing the default behaviour for non-versioned steps.
- Adding new workflow DSL constructs beyond iteration metadata.
- Redesigning suspension signalling or lease extension logic.

## Measuring Success
- Adapter workflow store contract suites verify rewinds, cursor resets, and
  iteration metadata for auto-versioned steps across in-memory, Redis,
  Postgres, and SQLite adapters.
- Rewinding a versioned step deletes all suffixed checkpoints while leaving
  earlier steps intact and sets `suspensionData.iteration` to the next attempt.
- `WorkflowStore.get` consistently reports the cursor based on logical step
  order even if multiple suffixed checkpoints exist for earlier iterations.

## Rollout
- Ship the spec delta, contract tests, and store fixes together so adapters stay
  in lock-step.
