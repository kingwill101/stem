# stem_builder example

This example demonstrates:

- Annotated workflow/task definitions
- Generated `stemModule`
- Generated typed workflow refs (no manual workflow-name strings):
  - `StemWorkflowDefinitions.flow.call(...).startWithRuntime(runtime)`
  - `StemWorkflowDefinitions.userSignup.call(...).startWithRuntime(runtime)`
- Generated typed task definitions that use the shared `TaskCall` /
  `TaskDefinition.waitFor(...)` APIs
- Generated zero-arg task definitions with direct helpers:
  - `StemTaskDefinitions.enqueueAndWaitBuilderExamplePing(stem)`
- Generated workflow manifest via `stemModule.workflowManifest`
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


The generated bundle is the default integration surface:

- `StemWorkflowApp.inMemory(module: stemModule)`
- `StemWorkflowApp.fromUrl(..., module: stemModule)`
- `StemWorkflowApp.create(stemApp: ..., module: stemModule)`
- `StemClient.fromUrl(..., module: stemModule)` + `createWorkflowApp()`
