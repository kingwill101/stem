---
title: Annotated Workflows
---

Use `stem_builder` when you want workflow authoring to look like normal Dart
methods instead of manual `Flow(...)` or `WorkflowScript(...)` objects.

## What the generator gives you

After adding `part '<file>.stem.g.dart';` and running `build_runner`, the
generated file exposes:

- `stemFlows`
- `stemScripts`
- `stemTasks`
- `StemWorkflowNames`
- typed starter helpers like `startUserSignup(...)`

Wire those directly into `StemWorkflowApp`:

```dart
final workflowApp = await StemWorkflowApp.fromUrl(
  'memory://',
  flows: stemFlows,
  scripts: stemScripts,
  tasks: stemTasks,
);
```

## Two script entry styles

### Direct-call style

Use a plain `run(...)` when your annotated checkpoints only need serializable
parameters:

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
- typed task parameter decoding

For lower-level generator details, see
[`Core Concepts > stem_builder`](../core-concepts/stem-builder.md).
