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
- typed task definitions that use the shared `TaskCall` /
  `TaskDefinition.waitFor(...)` APIs

The generated task definitions are producer-safe: `Stem.enqueueCall(...)` can
publish from the definition metadata, so producer processes do not need to
register the worker handler locally just to enqueue typed task calls.

Wire the bundle directly into `StemWorkflowApp`:

```dart
final workflowApp = await StemWorkflowApp.fromUrl(
  'memory://',
  module: stemModule,
);
```

With `module: stemModule`, the workflow app infers the worker subscription
from the workflow queue plus the default queues declared on the bundled task
handlers. Set `workerConfig.subscription` explicitly only when you need extra
queues beyond those defaults.

If you centralize broker/backend wiring in a `StemClient`, give the client the
bundle once and then create workflow apps without repeating it:

```dart
final client = await StemClient.fromUrl('memory://', module: stemModule);
final workflowApp = await client.createWorkflowApp();
```

Use the generated workflow refs when you want a single typed handle for start
and wait operations:

```dart
final result = await StemWorkflowDefinitions.userSignup.startAndWait(
  workflowApp,
  params: 'user@example.com',
);
```

Annotated tasks use the same shared typed task surface:

```dart
final result = await StemTaskDefinitions.sendEmailTyped.enqueueAndWait(
  workflowApp,
  EmailDispatch(
    email: 'typed@example.com',
    subject: 'Welcome',
    body: 'Codec-backed DTO payloads',
    tags: ['welcome'],
  ),
);
```

## Script context injection

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

When you need runtime metadata, add an optional named injected context
parameter:

```dart
@WorkflowDefn(name: 'annotated.context_script', kind: WorkflowKind.script)
class AnnotatedContextScriptWorkflow {
  Future<Map<String, Object?>> run(
    String email,
    {WorkflowScriptContext? context}
  ) async {
    return captureContext(email);
  }

  @WorkflowStep(name: 'capture-context')
  Future<Map<String, Object?>> captureContext(
    String email,
    {WorkflowScriptStepContext? context}
  ) async {
    final ctx = context!;
    return {
      'workflow': ctx.workflow,
      'runId': ctx.runId,
      'stepName': ctx.stepName,
      'stepIndex': ctx.stepIndex,
    };
  }
}
```

This keeps one authoring model:

- plain direct method calls are still the default
- context is added only when you need it
- the injected context is not part of the durable payload shape

When a workflow needs to start another workflow, do it from a durable boundary:

- `FlowContext` and `WorkflowScriptStepContext` both implement
  `WorkflowCaller`, so prefer `ref.startAndWait(context, params: value)` inside
  flow steps and checkpoint methods
- pass `ttl:`, `parentRunId:`, or `cancellationPolicy:` directly to
  `ref.start(...)` / `ref.startAndWait(...)` for the normal override cases
- keep `context.prepareWorkflowStart(...)` for the rarer incremental-call
  cases where you actually want to build the start request step by step

Avoid starting child workflows from the raw `WorkflowScriptContext` body.

## Runnable example

Use `packages/stem/example/annotated_workflows` when you want a verified
example that demonstrates:

- `FlowContext`
- direct-call script checkpoints
- nested annotated checkpoint calls
- `WorkflowScriptContext`
- `WorkflowScriptStepContext`
- optional named context injection
- `TaskInvocationContext`
- codec-backed DTO workflow checkpoints and final workflow results
- typed task DTO input and result decoding

When you inspect run detail, the runtime now exposes `checkpoints` for script
workflows rather than reusing the flow-step view model.

## DTO rules

Generated workflow/task entrypoints support required positional business
parameters that are either:

- serializable values (`String`, numbers, bools, `List<T>`, `Map<String, T>`)
- codec-backed DTO classes that provide:
  - a string-keyed `toJson()` map (typically `Map<String, dynamic>`)
  - `factory Type.fromJson(Map<String, dynamic> json)` or an equivalent named
    `fromJson` constructor

Typed task results can use the same DTO convention.

Workflow inputs, checkpoint values, and final workflow results can use the same
DTO convention. The generated `PayloadCodec` persists the JSON form while
workflow code continues to work with typed objects.

For lower-level generator details, see
[`Core Concepts > stem_builder`](../core-concepts/stem-builder.md).
