<p align="center">
  <img src="../../.site/static/img/stem-logo.png" width="300" alt="Stem Logo" />
</p>

# stem_builder

[![pub package](https://img.shields.io/pub/v/stem_builder.svg)](https://pub.dev/packages/stem_builder)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.9.2-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](https://github.com/kingwill101/stem/blob/main/LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

Build-time code generator for annotated Stem workflows and tasks.

## Install

```bash
dart pub add stem_builder
```

Add the core runtime if you haven't already:

```bash
dart pub add stem
```

## Usage

Annotate workflows and tasks:

```dart
import 'package:stem/stem.dart';

part 'workflows.stem.g.dart';

@WorkflowDefn(name: 'hello.flow')
class HelloFlow {
  @WorkflowStep()
  Future<void> greet(String email) async {
    // ...
  }
}

@WorkflowDefn(name: 'hello.script', kind: WorkflowKind.script)
class HelloScript {
  Future<void> run(String email) async {
    await sendEmail(email);
  }

  @WorkflowStep()
  Future<void> sendEmail(String email) async {
    // builder routes this through durable script.step(...)
  }
}

@TaskDefn(name: 'hello.task')
Future<void> helloTask(
  String email,
  {TaskInvocationContext? context}
) async {
  // ...
}
```

Script workflows can use a plain `run(...)` method with no extra annotation.
When you need runtime metadata or an explicit `script.step(...)`, add an
optional named `WorkflowScriptContext? context` parameter.

The intended usage is to call annotated checkpoint methods directly from
`run(...)`:

```dart
Future<Map<String, Object?>> run(String email) async {
  final user = await createUser(email);
  await sendWelcomeEmail(email);
  await sendOneWeekCheckInEmail(email);
  return {'userId': user['id'], 'status': 'done'};
}
```

`stem_builder` generates a proxy subclass that rewrites those calls into
durable `script.step(...)` executions. The source method bodies stay readable,
while the generated part handles the workflow runtime plumbing.

Conceptually:

- `Flow`: declared steps are the execution plan
- script workflows: `run(...)` is the execution plan, and declared checkpoints
  are metadata for manifests/tooling

Script workflows use one entry model:

- start with a plain direct-call `run(String email, ...)`
- add an optional named injected context when you need runtime metadata or an
  explicit `script.step(...)` wrapper
  - `Future<T> run(String email, {WorkflowScriptContext? context})`
  - `Future<T> checkpoint(String email, {WorkflowScriptStepContext? context})`
- direct annotated checkpoint calls stay the default path

Supported context injection points:

- flow steps: `FlowContext`
- script runs: `WorkflowScriptContext`
- script checkpoints: `WorkflowScriptStepContext`
- tasks: `TaskInvocationContext`

Child workflows should be started from durable boundaries:

- `FlowContext.workflows` inside flow steps
- `WorkflowScriptStepContext.workflows` inside script checkpoints

Avoid starting child workflows directly from the raw
`WorkflowScriptContext` body unless you are explicitly handling replay
semantics yourself.

Serializable parameter rules are enforced by the generator:

- supported:
  - `String`, `bool`, `int`, `double`, `num`, `Object?`, `null`
  - `List<T>` where `T` is serializable
  - `Map<String, T>` where `T` is serializable
- supported DTOs:
  - Dart classes with `toJson()` plus a named `fromJson(...)` constructor
    taking `Map<String, Object?>`
- unsupported directly:
  - optional/named business parameters on generated workflow/task entrypoints

Typed task results can use the same DTO convention.

Workflow inputs, checkpoint values, and final workflow results can use the same
DTO convention. The generated `PayloadCodec` persists the JSON form while
workflow code continues to work with typed objects.

The intended DX is:

- define annotated workflows and tasks in one file
- add `part '<file>.stem.g.dart';`
- run `build_runner`
- pass generated `stemModule` into `StemWorkflowApp` or `StemClient`
- start workflows through generated workflow refs instead of raw
  workflow-name strings
- enqueue annotated tasks through `StemTaskDefinitions.*.call(...).enqueueWith(...)`
  instead of raw task-name strings

You can customize generated workflow ref names via `@WorkflowDefn`:

```dart
@WorkflowDefn(
  name: 'billing.daily_sync',
  starterName: 'DailyBilling',
  nameField: 'dailyBilling',
  kind: WorkflowKind.script,
)
class BillingWorkflow {
  Future<void> run(String tenant) async {}
}
```

Run build_runner to generate `*.stem.g.dart` part files:

```bash
dart run build_runner build
```

The generated part exports a bundle plus typed helpers so you can avoid raw
workflow-name and task-name strings (for example
`StemWorkflowDefinitions.userSignup.call((email: 'user@example.com'))` or
`StemTaskDefinitions.builderExampleTask.call({...}).enqueueWith(stem)`).

Generated output includes:

- `stemModule`
- `StemWorkflowDefinitions`
- `StemTaskDefinitions`
- typed `TaskDefinition` objects that use the shared `TaskCall` /
  `TaskDefinition.waitFor(...)` APIs from `stem`

Generated task definitions are producer-safe. `Stem.enqueueCall(...)` can use
the definition metadata directly, so a producer can publish typed task calls
without registering the worker handler locally first.

## Wiring Into StemWorkflowApp

For the common case, pass the generated bundle directly to `StemWorkflowApp`:

```dart
final workflowApp = await StemWorkflowApp.fromUrl(
  'redis://localhost:6379',
  module: stemModule,
);

final result = await StemWorkflowDefinitions.userSignup
    .call((email: 'user@example.com'))
    .startAndWaitWithApp(workflowApp);
```

When you use `module: stemModule`, the workflow app infers the worker
subscription from the workflow queue plus the default queues declared on the
bundled task handlers. Override `workerConfig.subscription` only when your
routing sends work to additional queues.

If your application already owns a `StemApp`, reuse it:

```dart
final stemApp = await StemApp.fromUrl(
  'redis://localhost:6379',
  adapters: const [StemRedisAdapter()],
  module: stemModule,
);

final workflowApp = await StemWorkflowApp.create(
  stemApp: stemApp,
  module: stemModule,
);
```

For task-only services, use the same bundle directly with `StemApp`:

```dart
final taskApp = await StemApp.fromUrl(
  'redis://localhost:6379',
  adapters: const [StemRedisAdapter()],
  module: stemModule,
);
```

Plain `StemApp` bootstrap also infers task queue subscriptions from the
bundled task handlers when `workerConfig.subscription` is omitted.

If you already centralize wiring in a `StemClient`, prefer the shared-client
path:

```dart
final client = await StemClient.fromUrl(
  'redis://localhost:6379',
  adapters: const [StemRedisAdapter()],
  module: stemModule,
);

final workflowApp = await client.createWorkflowApp();
```

If you reuse an existing `StemApp`, its worker subscription stays in charge.
The module-based queue inference only applies when `StemWorkflowApp` is
creating the worker for you.

The generated workflow refs work on `WorkflowRuntime` too:

```dart
final runtime = workflowApp.runtime;
final runId = await StemWorkflowDefinitions.userSignup
    .call((email: 'user@example.com'))
    .startWithRuntime(runtime);
await runtime.executeRun(runId);
```

Annotated tasks also get generated definitions:

```dart
final taskId = await StemTaskDefinitions.builderExampleTask
    .call(const {'kind': 'welcome'})
    .enqueueWith(workflowApp.app.stem);
```

## Examples

See [`example/README.md`](example/README.md) for runnable examples, including:

- Generated registration + execution with `StemWorkflowApp`
- Runtime manifest + run detail views with `WorkflowRuntime`
- Plain direct-call script checkpoints and context-aware script checkpoints
- Typed `@TaskDefn` parameters with `TaskInvocationContext`
