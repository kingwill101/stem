# stem_builder example

This example demonstrates:

- Annotated workflow/task definitions
- Generated `registerStemDefinitions(...)`
- Generated app bootstrap helpers:
  - `createStemGeneratedInMemoryApp()`
  - `createStemGeneratedWorkflowApp(stemApp: ...)`
- Generated typed workflow starters (no manual workflow-name strings):
  - `runtime.startFlow(...)`
  - `runtime.startUserSignup(email: ...)`
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

The checked-in `lib/definitions.stem.g.dart` is only a starter snapshot; rerun
`build_runner` after changing annotations.


The generated helper APIs are convenience wrappers. The underlying public
`StemWorkflowApp` API also accepts `scripts`, `flows`, and `tasks` directly, so
you can wire generated definitions into a larger app without manual task
registration loops.
