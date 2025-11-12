# Design: Fake clock for workflow stores

## Overview
We add a `WorkflowClock` interface with a `now()` getter returning `DateTime`. The default implementation wraps `DateTime.now`. Tests can inject a mutable/fake clock that allows manual advancement.

## Integration Points
- `WorkflowRuntime` receives a `WorkflowClock` (default real clock) and uses it for all time comparisons (`DateTime.now()` calls).
- `WorkflowStore` operations that rely on timestamps get passed the current clock time by the runtime (e.g. when calling `suspendUntil`, `dueRuns`).
- In-memory store uses the provided timestamps without calling `DateTime.now` directly.
- Adapter tests can construct runtime/store combos with a fake clock to simulate time passing instantly.

## Risks
Minimal; ensure we thread the clock consistently and provide sane defaults.
