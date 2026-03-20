---
title: Context and Serialization
---

Stem injects context objects at specific points in the workflow/task lifecycle.
Everything else that crosses a durable boundary must be serializable.

## Supported context injection points

- flow steps: `FlowContext` or `WorkflowExecutionContext`
- script runs: `WorkflowScriptContext`
- script checkpoints: `WorkflowScriptStepContext` or
  `WorkflowExecutionContext`
- tasks: `TaskExecutionContext`

Those context objects are not part of the persisted payload shape. They are
injected by the runtime when the handler executes.

For annotated workflows/tasks, the preferred shape is an optional named context
parameter:

- `Future<T> run(String email, {WorkflowScriptContext? context})`
- `Future<T> checkpoint(String email, {WorkflowExecutionContext? context})`
- `Future<T> step({WorkflowExecutionContext? context})`
- `Future<void> task(String id, {TaskExecutionContext? context})`

## What context gives you

Depending on the context type, you can access:

- `workflow`
- `runId`
- `stepName`
- `stepIndex`
- `iteration`
- workflow params and previous results
- `param<T>()` / `requiredParam<T>()` for typed access to workflow start
  params
- `paramsAs(codec: ...)`, `paramsJson<T>()`, or `paramsVersionedJson<T>()`
  for decoding the full workflow start payload as one DTO
- `paramJson<T>()`, `paramVersionedJson<T>()`, or
  `requiredParamJson<T>()` for nested DTO params without a separate codec
  constant
- `paramListJson<T>()`, `paramListVersionedJson<T>()`, or
  `requiredParamListJson<T>()` for lists of nested DTO params without a
  separate codec constant
- `previousValue<T>()` / `requiredPreviousValue<T>()` for typed access to the
  prior step or checkpoint result
- `previousJson<T>()`, `previousVersionedJson<T>()`,
  `requiredPreviousJson<T>()`, or `requiredPreviousVersionedJson<T>()` for
  prior DTO results without a separate codec constant
- `sleepUntilResumed(...)` for common sleep/retry loops
- `waitForEventValue<T>(...)` for common event waits
- `waitForEventValueJson<T>(...)` or
  `waitForEventValueVersionedJson<T>(...)` for DTO event waits without a
  separate codec constant
- `event.awaitOn(step)` when a flow deliberately wants the lower-level
  `FlowStepControl` suspend-first path on a typed event ref
- `sleepJson(...)`, `sleepVersionedJson(...)`, `awaitEventJson(...)`,
  `awaitEventVersionedJson(...)`, and `FlowStepControl.awaitTopicJson(...)`
  when lower-level suspension directives still need DTO metadata without a
  separate codec constant
- `control.dataJson(...)`, `control.dataVersionedJson(...)`, or
  `control.dataAs(codec: ...)` when you inspect a lower-level
  `FlowStepControl` directly
- `takeResumeData()` for event-driven resumes
- `takeResumeValue<T>(codec: ...)` for typed event-driven resumes
- `takeResumeJson<T>(...)` or `takeResumeVersionedJson<T>(...)` for DTO
  event-driven resumes without a separate codec constant
- `idempotencyKey(...)`
- direct child-workflow start helpers such as
  `ref.start(context, params: value)` and
  `ref.startAndWait(context, params: value)`
- direct task enqueue APIs because `WorkflowExecutionContext` and
  `TaskExecutionContext` both implement `TaskEnqueuer`
- `argsAs(codec: ...)`, `argsJson<T>()`, or `argsVersionedJson<T>()` for
  decoding the full task-arg payload as one DTO inside manual task handlers
- `argJson<T>()`, `argVersionedJson<T>()`, `argListJson<T>()`, or
  `argListVersionedJson<T>()` when only one nested arg entry needs DTO decode
- task metadata like `id`, `attempt`, `meta`

Child workflow starts belong in durable boundaries:

- `ref.start(context, params: value)` inside flow steps
- `ref.startAndWait(context, params: value)` inside script checkpoints
- pass `ttl:`, `parentRunId:`, or `cancellationPolicy:` directly to those
  helpers for the normal override cases
- keep `context.prepareStart(...)` for incremental-call assembly when
  you genuinely need to build the start request step by step

Do not treat the raw `WorkflowScriptContext` body as a safe place for child
starts or other replay-sensitive side effects.

## Serializable parameter rules

Supported shapes:

- `String`
- `bool`
- `int`
- `double`
- `num`
- JSON-like scalar values (`Object?` only when the runtime value is itself
  serializable)
- `List<T>` where `T` is serializable
- `Map<String, T>` where `T` is serializable

Unsupported directly:

- arbitrary Dart class instances
- non-string map keys
- annotated workflow/task method signatures with optional or named business
  parameters

If you have a domain object, prefer a codec-backed DTO:

```dart
class OrderRequest {
  const OrderRequest({required this.id, required this.customerId});

  final String id;
  final String customerId;

  Map<String, dynamic> toJson() => {'id': id, 'customerId': customerId};

  factory OrderRequest.fromJson(Map<String, dynamic> json) {
    return OrderRequest(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
    );
  }
}
```

Generated workflow refs and task definitions will persist the JSON form while
your workflow/task code keeps working with the typed object. The restriction
still applies to the annotated business method signatures that `stem_builder`
lowers into workflow/task definitions.

The same rule applies to workflow resume events: `emitValue(...)` can take a
typed DTO plus a `PayloadCodec<T>`, but the codec must still encode to a
string-keyed map because watcher persistence and event delivery are map-based
today.

For normal DTOs that expose `toJson()` and `Type.fromJson(...)`, prefer
`PayloadCodec<T>.json(...)`. Drop down to `PayloadCodec<T>.map(...)` when you
need a custom map encoder or a nonstandard decode function.

If the DTO payload shape is expected to evolve, use
`PayloadCodec<T>.versionedJson(...)`. That persists a reserved
`__stemPayloadVersion` field beside the JSON payload and gives the decoder the
stored version so it can read older shapes explicitly.

For manual flows and scripts, prefer the typed workflow param helpers before
dropping to raw map casts:

```dart
final request = ctx.paramsJson<OrderRequest>(
  decode: OrderRequest.fromJson,
);
final userId = ctx.requiredParam<String>('userId');
final draft = ctx.requiredParam<ApprovalDraft>(
  'draft',
  codec: approvalDraftCodec,
);
```

For manual tasks, the same pattern applies to the full arg payload:

```dart
final request = context.argsJson<OrderRequest>(
  decode: OrderRequest.fromJson,
);
```

## Practical rule

When you need context metadata, add the appropriate optional named context
parameter. When you need business input, make it a required positional
serializable value.

Prefer the higher-level helpers first:

- `sleepUntilResumed(...)` when the step/checkpoint should pause once and
  continue on resume
- `waitForEventValue<T>(...)` when the step/checkpoint is waiting on one event

Drop down to `takeResumeData()`, `takeResumeValue<T>(...)`,
`takeResumeJson<T>(...)`, or `takeResumeVersionedJson<T>(...)` only when you
need custom branching around resume payloads.

The runnable `annotated_workflows` example demonstrates both the context-aware
and plain serializable forms.
