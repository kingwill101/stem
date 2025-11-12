# Design: Workflow DSL facade

## Context
- Absurd's workflows expose a `TaskContext` with `step`, `await`, and `sleep`
  helpers so authors can express durability in one async function.
- Stem today forces users to register each `flow.step('name', handler)` and wire
  state through `FlowContext`, which feels lower-level and is easy to misuse.
- We want an additive facade that translates ergonomic code into the existing
  `WorkflowDefinition` so stores/runtimes remain unchanged.

## Proposed API
```dart
final workflow = WorkflowScript.define('orders', (script) async {
  final checkout = await script.step(
    'checkout',
    () async => await chargeCustomer(script.params['userId'] as String),
  );

  await script.versionedStep(
    'pollShipment',
    autoVersion: true,
    (iteration) async {
      final status = await fetchShipment(checkout.id);
      if (status.isComplete) {
        return status;
      }
      await script.sleep(const Duration(minutes: 5));
      return WorkflowRepeat.resume();
    },
  );
});
```

- `WorkflowScript` (name TBD) generates a `WorkflowDefinition`.
- `script.step` persists automatically like `FlowBuilder.step`, returning the
  value saved in the checkpoint. Optional `autoVersion` support mirrors the
  builder.
- `script.sleep`/`script.awaitEvent` delegate to `FlowContext.sleep/awaitEvent`.
- `WorkflowRepeat.resume()` (or similar) signals the facade to keep invoking the
  current step; otherwise completion advances to the next step.

## Execution model
- The facade compiles the async function into a list of `FlowStep` objects.
- Each `script.step` callback becomes a `FlowStep` handler.
- The script stores intermediate results in a light context object so later
  calls can `await script.step('foo', ...)` and receive the persisted value.
- For `sleep/awaitEvent`, the facade forwards to the underlying `FlowContext`
  methods but also records enough intent so replayed calls no-op when the resume
  payload indicates progress (similar to guidance in docs).

## Testing strategy
- Unit tests ensuring `WorkflowScript` translates to the expected set of
  `FlowStep`s and replays correctly with the in-memory store.
- Adapter contract additions that run the facade against Redis/Postgres/SQLite
  to guarantee durability parity.
- Example workflow in `packages/stem/example/`.

## Alternatives considered
- Macros or code generation: rejected to keep API first-class and dynamic.
- Replacing `FlowBuilder`: rejected for backward compatibility.

## Open questions
- Naming for the facade (`WorkflowScript`, `WorkflowPlan`, etc.).
- How to signal “loop again” elegantly (`WorkflowRepeat.resume()` placeholder).
