---
title: stem_builder
sidebar_label: stem_builder
sidebar_position: 15
slug: /core-concepts/stem-builder
---

`stem_builder` generates workflow/task definitions, manifests, helper output,
and typed workflow refs from annotations, so you can avoid stringly-typed
wiring.

This page focuses on the generator itself. For the workflow authoring model and
durable runtime behavior, start with the top-level
[Workflows](../workflows/index.md) section, especially
[Annotated Workflows](../workflows/annotated-workflows.md).

For script workflows, generated checkpoints are introspection metadata. The
actual execution plan still comes from `run(...)`.

## Install

```bash
dart pub add stem
dart pub add --dev build_runner stem_builder
```

## Define Annotated Workflows and Tasks

```dart
import 'package:stem/stem.dart';

part 'workflow_defs.stem.g.dart';

@WorkflowDefn(
  name: 'commerce.user_signup',
  kind: WorkflowKind.script,
  starterName: 'UserSignup',
)
class UserSignupWorkflow {
  Future<Map<String, Object?>> run(String email) async {
    final user = await createUser(email);
    await sendWelcomeEmail(email);
    return {'userId': user['id'], 'status': 'done'};
  }

  @WorkflowStep(name: 'create-user')
  Future<Map<String, Object?>> createUser(String email) async {
    return {'id': 'usr-$email'};
  }

  @WorkflowStep(name: 'send-welcome-email')
  Future<void> sendWelcomeEmail(String email) async {}
}

@TaskDefn(name: 'commerce.audit.log', runInIsolate: false)
Future<void> logAudit(
  String event,
  String id, {
  TaskExecutionContext? context,
}) async {
  final ctx = context!;
  ctx.progress(1.0, data: {'event': event, 'id': id});
}
```

## Generate

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated output (`workflow_defs.stem.g.dart`) includes:

- `stemModule`
- typed workflow refs like `StemWorkflowDefinitions.userSignup`
- typed task definitions that use the shared `TaskCall` /
  `TaskDefinition.waitFor(...)` APIs

## Wire Into StemWorkflowApp

Use the generated definitions/helpers directly with `StemWorkflowApp`:

```dart
final workflowApp = await StemWorkflowApp.fromUrl(
  'memory://',
  module: stemModule,
);

await workflowApp.start();
final result = await StemWorkflowDefinitions.userSignup.startAndWait(
  workflowApp,
  params: 'user@example.com',
);
```

When you pass `module: stemModule`, the workflow app infers the worker
subscription from the workflow queue plus the default queues declared on the
bundled task handlers. Explicit subscriptions are still available for advanced
routing.

If your service needs more than one generated or hand-written bundle, merge
them before bootstrap:

```dart
final module = StemModule.merge([authModule, billingModule, stemModule]);
final workflowApp = await StemWorkflowApp.inMemory(module: module);
```

`StemModule.merge(...)` fails fast when modules declare conflicting task or
workflow names.

If you do not want to pre-merge them yourself, bootstrap helpers also accept
`modules:` directly:

```dart
final workflowApp = await StemWorkflowApp.inMemory(
  modules: [authModule, billingModule, stemModule],
);
```

The same bundle-first path works for plain task apps too:

```dart
final taskApp = await StemApp.fromUrl(
  'redis://localhost:6379',
  adapters: const [StemRedisAdapter()],
  module: stemModule,
);
```

If you need to attach generated or hand-written task definitions after
bootstrap, use the app helpers:

- `registerTask(...)` / `registerTasks(...)`
- `registerModule(...)` / `registerModules(...)`

When debugging bootstrap wiring, inspect the queue set a bundle implies before
you create the app:

```dart
final queues = stemModule.requiredWorkflowQueues(
  continuationQueue: 'workflow-continue',
  executionQueue: 'workflow-step',
);
```

If you are wiring a worker manually, the module can also give you the exact
subscription directly:

```dart
final subscription = stemModule.requiredWorkflowSubscription(
  continuationQueue: 'workflow-continue',
  executionQueue: 'workflow-step',
);
```

If you already manage a `StemApp` for a larger service, reuse it instead of
bootstrapping a second app:

```dart
final stemApp = await StemApp.fromUrl(
  'redis://localhost:6379',
  adapters: const [StemRedisAdapter()],
  module: stemModule,
  workerConfig: StemWorkerConfig(
    queue: 'workflow',
    subscription: RoutingSubscription(
      queues: ['workflow', 'default'],
    ),
  ),
);

final workflowApp = await stemApp.createWorkflowApp();
```

That shared-app path reuses the existing worker, so it only works when the
worker already covers the workflow queue plus the task queues your workflows
need. If you want automatic queue inference, prefer `StemClient`.

For task-only services, the same bundle works directly with `StemApp`:

```dart
final taskApp = await StemApp.fromUrl(
  'redis://localhost:6379',
  adapters: const [StemRedisAdapter()],
  module: stemModule,
);
```

Plain `StemApp` bootstrap infers task queue subscriptions from the bundled or
explicitly supplied task handlers when `workerConfig.subscription` is omitted,
and it lazy-starts on the first enqueue or wait call.

If you already centralize broker/backend wiring in a `StemClient`, prefer the
shared-client path:

```dart
final client = await StemClient.fromUrl(
  'redis://localhost:6379',
  adapters: const [StemRedisAdapter()],
  module: stemModule,
);

final workflowApp = await client.createWorkflowApp();
```

If you reuse an existing `StemApp`, its worker subscription remains your
responsibility. Workflow-side queue inference only applies when the workflow
app is creating the worker itself.

## Parameter and Signature Rules

- Business parameters must be required positional values that are either
  serializable or codec-backed DTOs.
- Script workflow `run(...)` can be plain (no annotation required).
- Checkpoint methods use `@WorkflowStep`.
- Plain `run(...)` is best when called checkpoint methods only need
  serializable
  parameters.
- When you need runtime metadata, add an optional named injected context
  parameter:
  - `WorkflowScriptContext? context` on `run(...)`
  - `WorkflowExecutionContext? context` on flow steps or checkpoint methods
- DTO classes are supported when they provide:
  - a string-keyed `toJson()` map (typically `Map<String, dynamic>`)
  - `factory Type.fromJson(Map<String, dynamic> json)` or an equivalent named
    `fromJson` constructor
- Typed task results can use the same DTO convention.
- Workflow inputs, checkpoint values, and final workflow results can use the
  same DTO convention. The generated `PayloadCodec` persists the JSON form
  while workflow code continues to work with typed objects.
- Runtime detail surfaces flow `steps` and script `checkpoints` separately.
