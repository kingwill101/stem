# Annotated Workflows Example

This example shows how to use `@WorkflowDefn`, `@WorkflowStep`, and `@TaskDefn`
with the `stem_builder` bundle generator.

It now demonstrates the generated script-proxy behavior explicitly:
- a flow step using `FlowContext`
- `run(WelcomeRequest request)` calls annotated step methods directly
- `prepareWelcome(...)` calls other annotated steps
- `deliverWelcome(...)` calls another annotated step from inside an annotated
  step
- a second script workflow uses `@WorkflowRun()` plus `WorkflowScriptStepContext`
  to expose `runId`, `workflow`, `stepName`, `stepIndex`, and idempotency keys
- a plain script workflow that returns a codec-backed DTO result and persists a
  codec-backed DTO checkpoint value
- a typed `@TaskDefn` using `TaskInvocationContext` plus codec-backed DTO
  input/output types

When you run the example, it prints:
- the flow result with `FlowContext` metadata
- the plain script result
- the persisted step order for the plain script workflow
- the persisted JSON form of the plain script DTO checkpoint and DTO result
- the context-aware script result with workflow metadata
- the persisted JSON form of the context-aware DTO result
- the persisted step order for the context-aware workflow
- the typed task result showing a decoded DTO result and task invocation
  metadata

The generated file exposes:

- `stemModule`
- `StemWorkflowDefinitions`
- typed workflow refs for `StemWorkflowApp` and `WorkflowRuntime`
- typed task definitions, enqueue helpers, and typed result wait helpers

## Serializable parameter rules

For `stem_builder`, generated workflow/task entrypoints support required
positional parameters that are either serializable values or codec-backed DTO
types:

- `String`, `bool`, `int`, `double`, `num`, `Object?`, `null`
- `List<T>` where `T` is serializable
- `Map<String, T>` where `T` is serializable
- Dart classes with:
  - `Map<String, Object?> toJson()`
  - `factory Type.fromJson(Map<String, Object?> json)` or an equivalent named
    `fromJson` constructor

Typed task results can use the same DTO convention.

Workflow inputs, checkpoint values, and final workflow results can use the same
DTO convention. The generated `PayloadCodec` persists the JSON form while the
workflow continues to work with typed objects.

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

## Regenerate the bundle

```bash
dart run build_runner build --delete-conflicting-outputs
```

The generated file is `lib/definitions.stem.g.dart`.
