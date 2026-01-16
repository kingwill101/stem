# Annotated Workflows Example

This example shows how to use `@WorkflowDefn`, `@WorkflowStep`, and `@TaskDefn`
with the `stem_builder` registry generator.

## Run

```bash
cd packages/stem/example/annotated_workflows
dart run bin/main.dart
```

## Regenerate the registry

```bash
dart run build_runner build
```

The generated file is `lib/stem_registry.g.dart`.
