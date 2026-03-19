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

## What context gives you

Depending on the context type, you can access:

- `workflow`
- `runId`
- `stepName`
- `stepIndex`
- `iteration`
- workflow params and previous results
- `takeResumeData()` for event-driven resumes
- `takeResumeValue<T>(codec: ...)` for typed event-driven resumes
- `idempotencyKey(...)`
- task metadata like `id`, `attempt`, `meta`

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

## Practical rule

When you need context metadata, add the appropriate context parameter first.
When you need business input, make it a required positional serializable value
after the context parameter.

The runnable `annotated_workflows` example demonstrates both the context-aware
and plain serializable forms.
