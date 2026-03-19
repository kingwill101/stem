---
title: Annotated Workflows
---

Use `stem_builder` when you want workflow authoring to look like normal Dart
methods instead of manual `Flow(...)` or `WorkflowScript(...)` objects.

## What the generator gives you

After adding `part '<file>.stem.g.dart';` and running `build_runner`, the
generated file exposes:

- `stemModule`
- `StemWorkflowDefinitions`
- `StemTaskDefinitions`
- typed workflow refs like `StemWorkflowDefinitions.userSignup`
- typed enqueue helpers like `enqueueSendEmailTyped(...)`
- typed result wait helpers like `waitForSendEmailTyped(...)`

Wire the bundle directly into `StemWorkflowApp`:

```dart
final workflowApp = await StemWorkflowApp.fromUrl(
  'memory://',
  module: stemModule,
);
```

Use the generated workflow refs when you want a single typed handle for start
and wait operations:

```dart
final result = await StemWorkflowDefinitions.userSignup
    .call((email: 'user@example.com'))
    .startAndWaitWithApp(workflowApp);
```

## Two script entry styles

### Direct-call style

Use a plain `run(...)` when your annotated checkpoints only need serializable
values or codec-backed DTO parameters:

```dart
@WorkflowDefn(name: 'builder.example.user_signup', kind: WorkflowKind.script)
class UserSignupWorkflow {
  Future<Map<String, Object?>> run(String email) async {
    final user = await createUser(email);
    await sendWelcomeEmail(email);
    return {'userId': user['id'], 'status': 'done'};
  }

  @WorkflowStep(name: 'create-user')
  Future<Map<String, Object?>> createUser(String email) async {
    return {'id': 'user:$email'};
  }

  @WorkflowStep(name: 'send-welcome-email')
  Future<void> sendWelcomeEmail(String email) async {}
}
```

The generator rewrites those calls into durable checkpoint boundaries in the
generated proxy class.

### Context-aware style

Use `@WorkflowRun()` when you need to enter through `WorkflowScriptContext` so
the checkpoint body can receive `WorkflowScriptStepContext`:

```dart
@WorkflowDefn(name: 'annotated.context_script', kind: WorkflowKind.script)
class AnnotatedContextScriptWorkflow {
  @WorkflowRun()
  Future<Map<String, Object?>> run(
    WorkflowScriptContext script,
    String email,
  ) async {
    return script.step<Map<String, Object?>>(
      'enter-context-step',
      (ctx) => captureContext(ctx, email),
    );
  }

  @WorkflowStep(name: 'capture-context')
  Future<Map<String, Object?>> captureContext(
    WorkflowScriptStepContext ctx,
    String email,
  ) async {
    return {
      'workflow': ctx.workflow,
      'runId': ctx.runId,
      'stepName': ctx.stepName,
      'stepIndex': ctx.stepIndex,
    };
  }
}
```

Context-aware checkpoint methods are not meant to be called directly from a
plain `run(String ...)` signature. If a called step needs
`WorkflowScriptStepContext`, enter it through `@WorkflowRun()` plus
`WorkflowScriptContext`; plain direct-call style is for steps that consume only
serializable business parameters.

## Runnable example

Use `packages/stem/example/annotated_workflows` when you want a verified
example that demonstrates:

- `FlowContext`
- direct-call script checkpoints
- nested annotated checkpoint calls
- `WorkflowScriptContext`
- `WorkflowScriptStepContext`
- `TaskInvocationContext`
- codec-backed DTO workflow checkpoints and final workflow results
- typed task DTO input and result decoding

## DTO rules

Generated workflow/task entrypoints support required positional parameters that
are either:

- serializable values (`String`, numbers, bools, `List<T>`, `Map<String, T>`)
- codec-backed DTO classes that provide:
  - `Map<String, Object?> toJson()`
  - `factory Type.fromJson(Map<String, Object?> json)` or an equivalent named
    `fromJson` constructor

Typed task results can use the same DTO convention.

Workflow inputs, checkpoint values, and final workflow results can use the same
DTO convention. The generated `PayloadCodec` persists the JSON form while
workflow code continues to work with typed objects.

For lower-level generator details, see
[`Core Concepts > stem_builder`](../core-concepts/stem-builder.md).
