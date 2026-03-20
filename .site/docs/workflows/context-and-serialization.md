---
title: Context and Serialization
---

Stem injects context objects at specific points in the workflow/task lifecycle.
Everything else that crosses a durable boundary must be serializable.

## Supported context injection points

- flow steps: `FlowContext`
- script runs: `WorkflowScriptContext`
- script checkpoints: `WorkflowScriptStepContext`
- tasks: `TaskInvocationContext`

Those context objects are not part of the persisted payload shape. They are
injected by the runtime when the handler executes.

For annotated workflows/tasks, the preferred shape is an optional named context
parameter:

- `Future<T> run(String email, {WorkflowScriptContext? context})`
- `Future<T> checkpoint(String email, {WorkflowScriptStepContext? context})`
- `Future<T> step({FlowContext? context})`
- `Future<void> task(String id, {TaskInvocationContext? context})`

## What context gives you

Depending on the context type, you can access:

- `workflow`
- `runId`
- `stepName`
- `stepIndex`
- `iteration`
- workflow params and previous results
- `sleepUntilResumed(...)` for common sleep/retry loops
- `waitForEventValue<T>(...)` for common event waits
- `takeResumeData()` for event-driven resumes
- `takeResumeValue<T>(codec: ...)` for typed event-driven resumes
- `idempotencyKey(...)`
- direct child-workflow start helpers such as `ref.startWith(context, value)`
  and `ref.startAndWaitWith(context, value)`
- direct task enqueue APIs because `FlowContext`,
  `WorkflowScriptStepContext`, and `TaskInvocationContext` all implement
  `TaskEnqueuer`
- task metadata like `id`, `attempt`, `meta`

Child workflow starts belong in durable boundaries:

- `ref.startWith(context, value)` inside flow steps
- `ref.startAndWaitWith(context, value)` inside script checkpoints
- `context.startWorkflowBuilder(...)` when you need advanced overrides like
  `ttl(...)` or `cancellationPolicy(...)`

Do not treat the raw `WorkflowScriptContext` body as a safe place for child
starts or other replay-sensitive side effects.

## Serializable parameter rules

Supported shapes:

- `String`
- `bool`
- `int`
- `double`
- `num`
- JSON-like scalar values (`Object?` only when the runtime value is itself
  serializable)
- `List<T>` where `T` is serializable
- `Map<String, T>` where `T` is serializable

Unsupported directly:

- arbitrary Dart class instances
- non-string map keys
- annotated workflow/task method signatures with optional or named business
  parameters

If you have a domain object, prefer a codec-backed DTO:

```dart
class OrderRequest {
  const OrderRequest({required this.id, required this.customerId});

  final String id;
  final String customerId;

  Map<String, Object?> toJson() => {'id': id, 'customerId': customerId};

  factory OrderRequest.fromJson(Map<String, Object?> json) {
    return OrderRequest(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
    );
  }
}
```

Generated workflow refs and task definitions will persist the JSON form while
your workflow/task code keeps working with the typed object. The restriction
still applies to the annotated business method signatures that `stem_builder`
lowers into workflow/task definitions.

The same rule applies to workflow resume events: `emitValue(...)` can take a
typed DTO plus a `PayloadCodec<T>`, but the codec must still encode to a
`Map<String, Object?>` because watcher persistence and event delivery are
map-based today.

For map-shaped DTOs, prefer `PayloadCodec<T>.map(...)` over hand-written
`Object?` decode wrappers.

## Practical rule

When you need context metadata, add the appropriate optional named context
parameter. When you need business input, make it a required positional
serializable value.

Prefer the higher-level helpers first:

- `sleepUntilResumed(...)` when the step/checkpoint should pause once and
  continue on resume
- `waitForEventValue<T>(...)` when the step/checkpoint is waiting on one event

Drop down to `takeResumeData()` / `takeResumeValue<T>(...)` only when you need
custom branching around resume payloads.

The runnable `annotated_workflows` example demonstrates both the context-aware
and plain serializable forms.
