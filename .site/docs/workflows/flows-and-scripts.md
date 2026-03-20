---
title: Flows and Scripts
---

Stem supports two workflow models. Both are durable. They differ in where the
execution plan lives.

## The distinction

| Model | Source of truth | Best for |
| --- | --- | --- |
| `Flow` | Declared steps | Explicit orchestration, clearer admin views, fixed step order |
| `WorkflowScript` | The Dart code in `run(...)` | Branching, loops, and function-style workflow authoring |

The confusing part is that both models expose step-like metadata. The difference
is that for script workflows those are **checkpoints**, not the plan itself.

- **Flow**: the runtime advances through the declared step list.
- **WorkflowScript**: the runtime re-enters `run(...)` and durable boundaries
  are created when `script.step(...)` executes.
- **Script checkpoints** exist for replay boundaries, manifests, dashboards,
  and tooling.

## Flow example

```dart title="lib/workflows/approvals_flow.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-flow

```

Manual flows can also derive a typed workflow ref from the definition:

```dart
final approvalsRef = approvalsFlow.ref<Map<String, Object?>>(
  encodeParams: (draft) => <String, Object?>{'draft': draft},
);
```

When a flow has no start params, start directly from the flow itself with
`flow.start(...)`, `flow.startAndWait(...)`, or `flow.prepareStart()`.
Use `ref0()` only when another API specifically needs a `NoArgsWorkflowRef`.

Use `Flow` when:

- the sequence of durable actions should be obvious from the definition
- each step maps cleanly to one business stage
- your operators care about a stable, declared step list

## Script example

```dart title="lib/workflows/retry_script.dart" file=<rootDir>/../packages/stem/example/docs_snippets/lib/workflows.dart#workflows-script

```

Manual scripts support the same pattern:

```dart
final retryRef = retryScript.ref<Map<String, Object?>>(
  encodeParams: (params) => params,
);
```

When a script has no start params, start directly from the script itself with
`retryScript.start(...)`, `retryScript.startAndWait(...)`, or
`retryScript.prepareStart()`. Use `ref0()` only when another API specifically
needs a `NoArgsWorkflowRef`.

Use `WorkflowScript` when:

- you want normal Dart control flow to define the run
- the workflow has branching or repeated patterns
- you want a more function-like authoring model

## Contexts in each model

- flow steps receive `FlowContext`
- script runs may receive `WorkflowScriptContext`
- script checkpoints may receive `WorkflowScriptStepContext`

The full injection and parameter rules are documented in
[Context and Serialization](./context-and-serialization.md).
