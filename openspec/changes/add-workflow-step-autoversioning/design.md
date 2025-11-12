# Design: Auto-versioned workflow steps

## Overview
We introduce an opt-in flag on workflow steps that allows the same logical step to execute multiple times across a run. When enabled, the runtime will suffix checkpoints with an iteration counter (`<name>#<n>`) and persist the counter in the run state so the next resume can continue from the correct iteration.

## API Sketch
- Extend `FlowStep` / `FlowBuilder.step` with an optional `autoVersion` (bool, default `false`).
- Expose the current iteration on `FlowContext` (e.g. `context.iteration`) for developer awareness and logging.
- Runtime derives a per-step iteration count from `RunState` and suspension metadata; for non-versioned steps the value is always `0`.

## Runtime Behaviour
1. When a versioned step starts, the runtime computes the next iteration index (starting at `0`). It derives a checkpoint key using `'$stepName#$iteration'`.
2. `WorkflowStore.readStep`/`saveStep` receive the derived key. This keeps store interfaces unchanged.
3. After the handler returns:
   - If it completed normally, we advance to the next base step and reset iteration state.
   - If it suspends, the runtime stores the current iteration in `RunState.suspensionData` so a resume can pick up with the same iteration.
4. On resume, the runtime reads the stored iteration and replays that version of the step. If the handler completes and marks a new iteration, the next pass increases the suffix.

## Persistence Changes
- `RunState` gets a new `Map<String, int> stepIterations` (or similar) tracking iteration counts per step. For the initial implementation we can embed it inside `suspensionData` and compute lazily; stores therefore need no schema change.
- When listing steps, we surface the expanded names (`foo#0`, `foo#1`, …) so operators can inspect all iterations.

## Backwards Compatibility
- The new flag defaults to `false`; existing flows keep single execution semantics.
- Old stores remain compatible because checkpoint keys are still unique strings written by the runtime. Migrating runs without the new flag requires no change.

## Risks & Mitigations
- **Iteration tracking drift** – If we miscount iterations, resuming could skip or duplicate work. Contract tests will cover completion, suspension, and failure at various iterations.
- **Operator visibility** – Because checkpoint names change, tooling should document the suffix convention; CLI output will show the full checkpoint names.
- **API surface growth** – Keep the flag optional to avoid breaking existing code; documentation will clearly indicate how and when to use auto-versioning.
