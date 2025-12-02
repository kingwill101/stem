---
title: Workflows
sidebar_label: Workflows
sidebar_position: 8
slug: /core-concepts/workflows
---

Stem Workflows let you orchestrate multi-step business processes with durable
state, typed results, automatic retries, and event-driven resumes. The
`StemWorkflowApp` helper wires together a `Stem` instance, workflow store,
event bus, and runtime so you can start runs, monitor progress, and interact
with suspended steps from one place.

## Runtime Overview

```dart title="bin/workflows.dart"
final workflowApp = await StemWorkflowApp.create(
  flows: [ApprovalsFlow.flow],
  scripts: [RetryScript.definition],
  broker: StemBrokerFactory.redis(url: 'redis://127.0.0.1:56379'),
  backend: StemBackendFactory.redis(url: 'redis://127.0.0.1:56379/1'),
  storeFactory: WorkflowStoreFactory.postgres(
    uri: 'postgresql://postgres:postgres@127.0.0.1:65432/stem',
  ),
  eventBusFactory: WorkflowEventBusFactory.redis(
    url: 'redis://127.0.0.1:56379/2',
  ),
  workerConfig: const StemWorkerConfig(queue: 'workflow'),
);

await workflowApp.start();
```

`StemWorkflowApp` exposes:

- `runtime` – registers `Flow`/`WorkflowScript` definitions and dequeues runs.
- `store` – persists checkpoints, suspension metadata, and results.
- `eventBus` – emits topics that resume waiting steps.
- `app` – the underlying `StemApp` (broker + result backend + worker).

## Declaring Typed Flows

Flows use the declarative DSL (`FlowBuilder`) to capture ordered steps. Specify
`Flow<T>` to document the completion type; generic metadata is preserved all the
way through `WorkflowResult<T>`.

```dart title="lib/workflows/approvals_flow.dart"
class ApprovalsFlow {
  static final flow = Flow<String>(
    name: 'approvals.flow',
    build: (flow) {
      flow.step('draft', (ctx) async {
        final payload = ctx.params['draft'] as Map<String, Object?>;
        return payload['documentId'];
      });

      flow.step('manager-review', (ctx) async {
        final resume = ctx.takeResumeData();
        if (resume == null) {
          await ctx.awaitEvent('approvals.manager');
          return null;
        }
        return resume;
      });

      flow.step('finalize', (ctx) async {
        final approvedBy = ctx.previousResult as String?;
        return 'approved-by:$approvedBy';
      });
    },
  ).definition;
}

// Register with the runtime
workflowApp.runtime.registerWorkflow(ApprovalsFlow.flow);
```

Steps re-run from the top after every suspension, so handlers must be
idempotent and rely on `FlowContext` helpers: `iteration`, `takeResumeData`,
`sleep`, `awaitEvent`, `idempotencyKey`, and persisted step outputs.

## Workflow Scripts

`WorkflowScript` offers a higher-level facade that feels like a regular async
function. You still get typed results and step-level durability, but the DSL
handles `ctx.step` registration automatically.

```dart title="lib/workflows/retry_script.dart"
final retryScript = WorkflowScript(
  name: 'billing.retry-script',
  run: (script) async {
    final chargeId = await script.step<String>('charge', (ctx) async {
      final resume = ctx.takeResumeData();
      if (resume == null) {
        await ctx.awaitEvent('billing.charge.prepared');
        return 'pending';
      }
      return resume['chargeId'] as String;
    });

    final receipt = await script.step<String>('confirm', (ctx) async {
      ctx.idempotencyKey('confirm-$chargeId');
      return 'receipt-$chargeId';
    });

    return receipt;
  },
).definition;

workflowApp.runtime.registerWorkflow(retryScript);
```

Scripts can enable `autoVersion: true` inside `script.step` calls to track loop
iterations using the `stepName#iteration` naming convention.

## Starting & Awaiting Workflows

```dart title="bin/run_workflow.dart"
final runId = await workflowApp.startWorkflow(
  'approvals.flow',
  params: {'draft': {'documentId': 'doc-42'}},
  cancellationPolicy: const WorkflowCancellationPolicy(
    maxRunDuration: Duration(hours: 2),
    maxSuspendDuration: Duration(minutes: 30),
  ),
);

final result = await workflowApp.waitForCompletion<String>(
  runId,
  timeout: const Duration(minutes: 5),
);

if (result?.isCompleted == true) {
  print('Workflow finished with ${result!.value}');
} else {
  print('Workflow state: ${result?.status}');
}
```

`waitForCompletion<T>` returns a `WorkflowResult<T>` that includes the decoded
value, original `RunState`, and a `timedOut` flag so callers can decide whether
to keep polling or surface status upstream.

## Suspension, Events, and Groups of Runs

- `sleep(duration)` stores a wake-up timestamp; the runtime polls `dueRuns` and
  resumes those runs by re-enqueuing the internal workflow task.
- `awaitEvent(topic, deadline: ...)` registers durable watchers so external
  services can `emit(topic, payload)`. The payload becomes `resumeData` for the
  awaiting step.
- `runsWaitingOn(topic)` exposes all runs suspended on a channel—useful for CLI
  tooling or dashboards. After a topic resumes the runtime calls
  `markResumed(runId, data: suspensionData)` so flows can inspect the payload.

Because watchers and due runs are persisted in the `WorkflowStore`, you can
operate on *groups* of workflows (pause, resume, or inspect every run waiting on
a topic) even if no worker is currently online.

## Payload Encoders in Workflow Apps

Workflows execute on top of a `Stem` worker, so they inherit the same
`TaskPayloadEncoder` facilities as regular tasks. `StemWorkflowApp.create`
accepts either a shared `TaskPayloadEncoderRegistry` or explicit defaults:

```dart title="lib/workflows/bootstrap.dart"
final encoders = TaskPayloadEncoderRegistry(
  defaultArgsEncoder: const JsonTaskPayloadEncoder(),
  defaultResultEncoder: const Base64PayloadEncoder(),
);

final app = await StemWorkflowApp.create(
  flows: [ApprovalsFlow.flow],
  encoderRegistry: encoders,
  additionalEncoders: const [GzipPayloadEncoder()],
);
```

Every workflow run task stores the result encoder id in `RunState.resultMeta`,
and the internal tasks dispatched by workflows reuse the same registry—so
typed steps can safely emit encrypted/binary payloads while workers decode them
exactly once.

Need per-workflow overrides? Register custom encoders on individual task
handlers (via `TaskMetadata`) or attach a specialized encoder to a `Flow`/script
step that persists sensitive data in the workflow store.

## Tooling Tips

- Use `workflowApp.store.listRuns(...)` to filter by workflow/status when
  building admin dashboards.
- `workflowApp.runtime.emit(topic, payload)` is the canonical way to resume
  batches of runs waiting on external events.
- CLI integrations (see `stem workflow ...`) rely on the same store APIs, so
  keeping the store tidy (expired runs, watchers) ensures responsive tooling.
