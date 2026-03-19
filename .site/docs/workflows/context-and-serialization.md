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

If you have a domain object, encode it first:

```dart
final order = <String, Object?>{
  'id': 'ord_42',
  'customerId': 'cus_7',
  'totalCents': 1250,
};
```

Decode it inside the workflow or task body, not at the durable boundary.

Generated starter helpers may still expose named parameters as a wrapper over
the serialized params map. The restriction applies to the annotated business
method signatures that `stem_builder` lowers into workflow/task definitions.

## Practical rule

When you need context metadata, add the appropriate context parameter first.
When you need business input, make it a required positional serializable value
after the context parameter.

The runnable `annotated_workflows` example demonstrates both the context-aware
and plain serializable forms.
