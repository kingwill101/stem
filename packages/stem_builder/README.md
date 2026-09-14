<p align="center">
  <img src="../../.site/static/img/stem-logo.png" width="300" alt="Stem Logo" />
</p>

# stem_builder

[![pub package](https://img.shields.io/pub/v/stem_builder.svg)](https://pub.dev/packages/stem_builder)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.13-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](https://github.com/kingwill101/stem/blob/main/LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

Build-time code generator for annotated Stem workflows and tasks.

Generated `StemPayloadCodecs` fields remain `PayloadCodec<T>.json` conveniences.
`PayloadCodec<T>` implements the standard `dart:convert` contract
`Codec<T, Object?>`, including `encoder` and `decoder` converters. Handwritten
task/workflow codec arguments also accept any `Codec<T, Object?>`; generated
JSON DTO adapters and stored schema-version formats remain unchanged.

### Explicit payload codec bindings

For a non-JSON representation, bind a standard codec in the same library as
the annotated task or workflow:

```dart
@PayloadCodecDefn()
Codec<Order, Object?> get orderCodec => const OrderCodec();

@PayloadCodecDefn()
const Codec<List<Order>, Object?> ordersCodec = OrdersCodec();
```

The binding is library-local and matches the codec's `Codec<T, Object?>` type
argument exactly, including nullability. The generated part keeps a reference
to the annotated value (so a getter is evaluated once) and does not infer
generic codecs or use reflection. Generic DTOs, DTO collections, and other
unsupported generated shapes therefore require an explicit binding. A codec
owns its representation; map envelopes are still the runtime transport
envelope and codec output must follow the selected backend's contract.

The codec object itself must be non-nullable. `Codec<Order?, Object?>` can
encode nullable payloads; `Codec<Order, Object?>?` is not a valid binding.
Flow input widening must also preserve the codec representation: synthesized
JSON may widen `Order` to `Order?` for the same DTO, but a custom binding cannot
silently switch to synthesized JSON or a different custom binding.

## Install

```bash
dart pub add --dev stem_builder build_runner
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
  {TaskExecutionContext? context}
) async {
  // ...
}
```

Script workflows can use a plain `run(...)` method with no extra annotation.
When you need runtime metadata, add an optional named
`WorkflowScriptContext? context` parameter. The direct annotated checkpoint
call still stays the default path.

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

For flows, the first step's business parameters define the workflow input
contract. Later steps may read those parameters but must not introduce required
inputs absent from that contract or require incompatible types. Use the injected
context to read previous step results; a later parameter is not automatically
bound to the previous result.
Safe widening such as `int` to `num` or `String` to `String?` is accepted.
Codec-backed parameters must also retain a compatible payload representation;
type assignability alone does not make different DTO codecs interchangeable.

Task functions may return a value synchronously, a `Future<T>`, or a
`FutureOr<T>`; generated entrypoints normalize those forms to the runtime's
asynchronous handler contract. Synchronous collection results retain their full
types. Script entry methods and annotated script checkpoints retain their
documented `Future<T>` / `FutureOr<T>` contract.

Task names and workflow names must each be unique within a generated library.
Across libraries, compose modules explicitly and retain runtime conflict checks.
Use explicit `@WorkflowStep(name: ...)` identifiers when a Dart method may be
renamed without changing its persisted checkpoint identity.

Script workflows use one entry model:

- start with a plain direct-call `run(String email, ...)`
- add an optional named injected context when you need runtime metadata
  - `Future<T> run(String email, {WorkflowScriptContext? context})`
  - `Future<T> checkpoint(String email, {WorkflowExecutionContext? context})`
- direct annotated checkpoint calls stay the default path

Supported context injection points:

- flow steps: `FlowContext` or `WorkflowExecutionContext`
- script runs: `WorkflowScriptContext`
- script checkpoints: `WorkflowScriptStepContext` or
  `WorkflowExecutionContext`
- tasks: `TaskExecutionContext`

Durable workflow execution contexts enqueue tasks directly:

- `WorkflowExecutionContext.enqueue(...)`
- typed task definitions can target those contexts via `enqueue(...)`

Child workflows should be started from durable boundaries:

- `ref.start(context, params: value)` inside flow steps
- `ref.startAndWait(context, params: value)` inside script checkpoints
- pass `ttl:`, `parentRunId:`, or `cancellationPolicy:` directly to
  `ref.start(...)` / `ref.startAndWait(...)` for the normal override cases
- build an explicit transport request with `ref.buildStart(...)` only for the
  rarer low-level cases where you need to pass a `WorkflowStartCall` around

Avoid starting child workflows directly from the raw
`WorkflowScriptContext` body unless you are explicitly handling replay
semantics yourself.

Serializable parameter rules are enforced by the generator:

- supported:
  - `String`, `bool`, `int`, `double`, `num`, `Object?`, `null`
  - `List<T>` and `Map<String, T>` whose elements are supported primitive values
    or recursively supported lists/maps
- supported DTOs:
  - Non-generic Dart classes with `toJson()` plus a named `fromJson(...)` constructor
    taking `Map<String, Object?>`
- supported with an exact `@PayloadCodecDefn()` binding:
  - concrete generic DTOs, collections of DTOs, and other codec-backed values
- unsupported:
  - optional/named business parameters on generated workflow/task entrypoints
  - unbound generic DTOs, collections of DTOs, and sets

Accepting `Object?` does not make arbitrary Dart objects persistable. The actual
value must satisfy the selected transport/backend contract. For custom
representations, declare a library-local codec binding or use core typed
definitions directly. The generator does not inspect or automatically bind a
host's runtime codec registry.

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
- enqueue annotated tasks through generated task definitions instead of raw
  task-name strings

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

The generated part exports a bundle plus typed refs/definitions so you can
avoid raw workflow-name and task-name strings (for example
`StemWorkflowDefinitions.userSignup.start(
workflowApp,
params: 'user@example.com',
)`
or `StemTaskDefinitions.builderExamplePing.enqueue(stem)`).

Generated output includes:

- `stemModule`
- `StemWorkflowDefinitions`
- `StemTaskDefinitions`
- typed `TaskDefinition` objects whose advanced explicit transport path uses
  `TaskCall`, alongside direct `enqueue(...)` / `enqueueAndWait(...)`

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

final result = await StemWorkflowDefinitions.userSignup.startAndWait(
  workflowApp,
  params: 'user@example.com',
);
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
  workerConfig: StemWorkerConfig(
    queue: 'workflow',
    subscription: RoutingSubscription(
      queues: ['workflow', 'default'],
    ),
  ),
);

final workflowApp = await stemApp.createWorkflowApp();
```

That shared-app path only works when the existing `StemApp` worker already
subscribes to the workflow queue plus any task queues the workflows need.
If you want subscription inference, prefer `StemClient.createWorkflowApp()`.

For task-only services, use the same bundle directly with `StemApp`:

```dart
final taskApp = await StemApp.fromUrl(
  'redis://localhost:6379',
  adapters: const [StemRedisAdapter()],
  module: stemModule,
);
```

Plain `StemApp` bootstrap also infers task queue subscriptions from the
bundled or explicitly supplied task handlers when
`workerConfig.subscription` is omitted. Start the app explicitly with
`await taskApp.start()` before enqueueing or waiting for work.

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
Workflow-side queue inference only applies when `StemWorkflowApp` is creating
the worker for you.

When you are intentionally using the low-level `WorkflowRuntime`, the
generated workflow refs work there too:

```dart
final runtime = workflowApp.runtime;
final runId = await StemWorkflowDefinitions.userSignup.start(
  runtime,
  params: 'user@example.com',
);
await workflowApp.executeRun(runId);
```

Annotated tasks also get generated definitions:

```dart
final taskId = await StemTaskDefinitions.builderExampleTask.enqueue(
  workflowApp,
  const {'kind': 'welcome'},
);
```

## Examples

See [`example/README.md`](example/README.md) for runnable examples, including:

- Generated registration + execution with `StemWorkflowApp`
- Runtime manifest + run detail views with `WorkflowRuntime`
- Plain direct-call script checkpoints and context-aware script checkpoints
- Typed `@TaskDefn` parameters with `TaskExecutionContext`
