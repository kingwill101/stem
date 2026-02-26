<p align="center">
  <img src="../../.site/static/img/stem-logo.png" width="300" alt="Stem Logo" />
</p>

# stem_builder

[![pub package](https://img.shields.io/pub/v/stem_builder.svg)](https://pub.dev/packages/stem_builder)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.9.2-blue.svg)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](https://github.com/kingwill101/stem/blob/main/LICENSE)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow.svg)](https://www.buymeacoffee.com/kingwill101)

Build-time registry generator for annotated Stem workflows and tasks.

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
  @WorkflowRun()
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
  TaskInvocationContext context,
  String email,
) async {
  // ...
}
```

`@WorkflowRun` may optionally take `WorkflowScriptContext` as its first
parameter, followed by required positional serializable parameters.

Run build_runner to generate `*.stem.g.dart` part files:

```bash
dart run build_runner build
```

The generated part exports helpers like `registerStemDefinitions`,
`createStemGeneratedWorkflowApp`, `createStemGeneratedInMemoryApp`, and typed
starters so you can avoid raw workflow-name strings (for example
`runtime.startScript(email: 'user@example.com')`).

## Examples

See [`example/README.md`](example/README.md) for runnable examples, including:

- Generated registration + execution with `StemWorkflowApp`
- Runtime manifest + run detail views with `WorkflowRuntime`
