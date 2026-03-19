# Annotated Workflows Example

This example shows how to use `@WorkflowDefn`, `@WorkflowStep`, and `@TaskDefn`
with the `stem_builder` registry generator.

It now demonstrates the generated script-proxy behavior explicitly:
- a flow step using `FlowContext`
- `run(String email)` calls annotated step methods directly
- `prepareWelcome(...)` calls other annotated steps
- `deliverWelcome(...)` calls another annotated step from inside an annotated
  step
- a second script workflow uses `@WorkflowRun()` plus `WorkflowScriptStepContext`
  to expose `runId`, `workflow`, `stepName`, `stepIndex`, and idempotency keys
- a typed `@TaskDefn` using `TaskInvocationContext` plus serializable scalar,
  `Map<String, Object?>`, and `List<Object?>` parameters

When you run the example, it prints:
- the flow result with `FlowContext` metadata
- the plain script result
- the persisted step order for the plain script workflow
- the context-aware script result with workflow metadata
- the persisted step order for the context-aware workflow
- the typed task result showing decoded serializable parameters and task
  invocation metadata

## Serializable parameter rules

For `stem_builder`, generated workflow/task entrypoints only support required
positional parameters that are serializable:

- `String`, `bool`, `int`, `double`, `num`, `Object?`, `null`
- `List<T>` where `T` is serializable
- `Map<String, T>` where `T` is serializable

Arbitrary Dart class instances are not supported directly. Encode them into a
serializable map first, then decode them inside your workflow or task if you
want a richer domain model.

## Run

```bash
cd packages/stem/example/annotated_workflows
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart run bin/main.dart
```

From the repo root:

```bash
task demo:annotated
```

## Regenerate the registry

```bash
dart run build_runner build --delete-conflicting-outputs
```

The generated file is `lib/definitions.stem.g.dart`.
