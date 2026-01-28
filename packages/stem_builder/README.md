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

@workflow.defn(name: 'hello.flow')
class HelloFlow {
  @workflow.step()
  Future<void> greet(FlowContext context) async {
    // ...
  }
}

@TaskDefn(name: 'hello.task')
Future<void> helloTask(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  // ...
}
```

Run build_runner to generate `lib/stem_registry.g.dart`:

```bash
dart run build_runner build
```

The generated registry exports `registerStemDefinitions` to register annotated
flows, scripts, and tasks with your `WorkflowRegistry` and `TaskRegistry`.
