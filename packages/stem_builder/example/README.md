# stem_builder example

This example demonstrates:

- Annotated workflow/task definitions
- Generated `registerStemDefinitions(...)`
- Generated app bootstrap helpers:
  - `createStemGeneratedInMemoryApp()`
  - `createStemGeneratedWorkflowApp(stemApp: ...)`
- Generated typed workflow starters (no manual workflow-name strings):
  - `runtime.startBuilderExampleFlow(...)`
  - `runtime.startBuilderExampleUserSignup(email: ...)`
- Generated `stemWorkflowManifest`
- Running generated definitions through `StemWorkflowApp`
- Runtime manifest + run/step metadata views via `WorkflowRuntime`

## Run

```bash
cd packages/stem_builder/example

dart pub get

dart run build_runner build

dart run bin/main.dart

dart run bin/runtime_metadata_views.dart
```

The checked-in `lib/stem_registry.g.dart` is only a starter snapshot; rerun
`build_runner` after changing annotations.
