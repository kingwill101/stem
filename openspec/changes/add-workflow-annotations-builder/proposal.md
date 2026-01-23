## Why
Define workflows and steps ergonomically (Temporal-style) while keeping Dart-friendly, tree-shakable registration without runtime reflection.

## What Changes
- Add workflow/task annotations (`@workflow.defn`, `@workflow.step`, `@task.defn`) for class/method and function ergonomics.
- Add a build_runner builder that generates registries and metadata for annotated workflows/tasks.
- Add runtime APIs to load generated registries and execute workflows/steps by definition name.
- Provide examples and documentation for the annotated flow.

## Impact
- Affected specs: workflow-definitions (new capability)
- Affected code: `packages/stem`, new builder package (name TBD), examples/tests
