# Annotated Workflows Example

This example shows how to use `@WorkflowDefn`, `@WorkflowStep`, and `@TaskDefn`
with the `stem_builder` registry generator.

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

## Regenerate the registry

```bash
dart run build_runner build --delete-conflicting-outputs
```

The generated file is `lib/definitions.stem.g.dart`.
