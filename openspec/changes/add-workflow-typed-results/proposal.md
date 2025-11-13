# Proposal: Typed workflow results

## Problem
Workflow authors can return arbitrary objects from flows or scripts, but
callers only receive a `RunState` with an `Object? result`. Every consumer must
manually cast the payload, plumb custom decoding, and remember to check the
status before trusting the shape. This leads to brittle glue code in examples,
CLI utilities, and services that orchestrate workflows because there is no
single typed surface for "wait for this workflow and give me the domain object
it produced".

## Goals
- Extend the existing workflow APIs with generic parameters so callers can
  declare result types up front (e.g. `Flow<OrderReceipt>`) and reuse the same
  types when waiting for completion.
- Update helpers such as `StemWorkflowApp.waitForCompletion` (and any runtime
  polling helpers) to surface the declared generic type together with run
  metadata instead of forcing consumers to cast `Object?`.
- Allow callers to plug in lightweight decoders when the workflow result is a
  structured map/JSON payload so conversions stay consistent and testable.
- Ensure in-memory and adapter-backed stores continue to persist raw results
  exactly once, with typed decoding happening only at the boundary, so existing
  workflows do not need to change how they persist checkpoints.

## Non-Goals
- Changing how `WorkflowStore` serializes checkpoints or run results.
- Enforcing static typing on every workflow step or intermediate checkpoint.
- Replacing the existing `waitForCompletion` helper (it remains for callers who
  need the full `RunState`).

## Measuring Success
- Sample apps/tests can call `await app.waitForCompletion<OrderReceipt>(
  runId, decode: OrderReceipt.fromJson)` and receive a typed object without
  manual casting while leveraging the familiar API.
- When a workflow fails, the typed helper surfaces the terminal status/error
  and does not attempt to decode payloads.
- Documentation clearly distinguishes between `waitForCompletion` (raw state)
  and the new typed helper so teams can choose the right API.
