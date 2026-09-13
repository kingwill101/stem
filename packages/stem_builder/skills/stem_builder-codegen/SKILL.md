---
name: stem_builder-codegen
description: >-
  Use when adding Stem annotations, generated task/workflow registries, DTO
  codecs, or build_runner configuration with stem_builder. Generate code from
  supported declarations and keep codec representations stable.
---

# stem_builder code generation

## Rules

- Add `stem` as a dependency and `stem_builder` plus `build_runner` as
  development dependencies. Annotation types are exported by `stem`.
- Add a `part 'name.stem.g.dart';` directive to the annotated library. Run
  `dart run build_runner build` (or `watch`) from the consuming package.
- Use `@WorkflowDefn` for flow or script classes and `@TaskDefn` for task
  functions. Give persisted tasks, workflows, and checkpoints explicit stable
  names when a Dart rename must not change identity.
- A flow's first step defines its input contract. Later steps may read prior
  results through the injected context; do not add required inputs that are
  absent from that contract.
- Script workflows use a plain `run(...)` method. Annotated checkpoint methods
  are called directly from `run`; the generated proxy routes them through
  durable `script.step(...)` execution.
- Supported context injection is deliberate: flow steps use `FlowContext` or
  `WorkflowExecutionContext`, script runs use `WorkflowScriptContext`, script
  checkpoints use `WorkflowScriptStepContext` or `WorkflowExecutionContext`,
  and typed task functions can inject `TaskExecutionContext`. Prefer typed
  serializable or codec-backed parameters; the context-plus-map signature is
  a legacy interoperability path, not a requirement for generated tasks.
- Use `@PayloadCodecDefn()` for a custom `Codec<T, Object?>` in the same
  library. The binding must be non-nullable as a value, and its generic type
  and representation must remain exact; generic DTOs and unsupported shapes
  need an explicit binding.
- Generated JSON DTO adapters and stored schema-version formats are not a
  license to change persisted names or representations casually. Regenerate
  after annotation changes and inspect the generated diff.
- Keep task and workflow names unique within one generated library. Compose
  multiple generated libraries/modules explicitly so runtime conflict checks
  remain active.

## Example

Save this annotated library as `lib/definitions.dart`, then generate its part:

```dart
import 'package:stem/stem.dart';

part 'definitions.stem.g.dart';

@WorkflowDefn(name: 'welcome')
class WelcomeFlow {
  @WorkflowStep(name: 'send')
  Future<void> send(String email) async {
    // Perform one durable step.
  }
}

@TaskDefn(name: 'welcome.audit')
Future<String> audit(String email) async => 'Audited $email';
```

For script workflows, add this class to the same annotated library:

```dart
@WorkflowDefn(name: 'welcome.script', kind: WorkflowKind.script)
class WelcomeScript {
  Future<void> run(String email) async {
    await send(email);
  }

  @WorkflowStep(name: 'send')
  Future<void> send(String email) async {
    // The generated proxy turns this into a durable checkpoint.
  }
}
```

## Validation checklist

1. Run the builder tests and an integration compile after changing
   annotations or generated output.
2. Check that generated names, codecs, and nullability match the declaration.
3. Run the generated registry through the same runtime registration path used
   by the application; generated source alone is not a worker.
