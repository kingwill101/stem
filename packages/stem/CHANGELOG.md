# Changelog

## 0.1.1

- Added `PayloadVersionRegistry<T>` plus registry-backed versioned factories
  for manual task definitions, workflow refs, workflow events, flows, and
  scripts.
- Added `Flow.versionedMap(...)`, `WorkflowScript.versionedMap(...)`,
  `WorkflowDefinition.flowVersionedMap(...)`, and
  `WorkflowDefinition.scriptVersionedMap(...)` for custom map workflow results
  that still persist `__stemPayloadVersion`.
- Added `TaskDefinition.versionedMap(...)` for custom map task args that
  should still persist `__stemPayloadVersion`, including the same
  version-aware stored-result decoding options as `versionedJson(...)`.
- Added `WorkflowEventRef.versionedMap(...)` and
  `WorkflowRef.versionedMap(...)` plus the matching
  `refVersionedMap(...)` helpers on `Flow`, `WorkflowScript`, and
  `WorkflowDefinition` for custom map payloads that still persist
  `__stemPayloadVersion`.
- Added `decodeResultVersionedJson:` to
  `WorkflowRef.json(...)` / `refJson(...)` so manual typed workflow refs can
  keep unversioned params while decoding a version-aware stored result.
- Added `decodeResultVersionedJson:` to `TaskDefinition.json(...)` so manual
  task definitions can keep unversioned DTO args while decoding a
  version-aware stored result.
- Added `decodeResultVersionedJson:` to
  `WorkflowRef.versionedJson(...)` / `refVersionedJson(...)` so manual typed
  workflow refs can derive version-aware result decoding alongside versioned
  params.
- Added `decodeResultVersionedJson:` to
  `TaskDefinition.versionedJson(...)` so argful manual task definitions can
  derive version-aware result decoding and result-encoder metadata.
- Refreshed runnable workflow/task examples to remove stale `.call(...)`
  transport usage and prefer the narrowed direct `start(...)` /
  `buildCall(...)` surfaces.
- Removed `WorkflowRef.call(...)` as a duplicate workflow-start convenience.
  The direct `start(...)` / `startAndWait(...)` helpers remain the happy path,
  and `buildStart(...)` remains the explicit prebuilt-call path.
- Removed `NoArgsWorkflowRef.prepareStart()` as a duplicate no-args builder
  wrapper. Use direct `start(...)` / `startAndWait(...)` for the happy path,
  or `ref0().asRef.buildStart(params: ())` when you need an explicit prebuilt
  call.
- Removed `TaskDefinition.call(...)` as a duplicate task-enqueue convenience.
  The direct `enqueue(...)` / `enqueueAndWait(...)` helpers remain the happy
  path, and `buildCall(args, ...)` remains the explicit prebuilt-call path.
- Removed the `TaskCall.enqueue(...)` / `enqueueAndWait(...)` and
  `WorkflowStartCall.start(...)` / `startAndWait(...)` dispatch wrappers.
  Prebuilt transport objects now dispatch explicitly through
  `TaskEnqueuer.enqueueCall(...)` and `WorkflowCaller.startWorkflowCall(...)`.
- Renamed read-side `...VersionedJson(...)` fallback args to
  `defaultVersion:` so decode helpers no longer imply they are choosing the
  persisted schema version on already-stored payloads.
- Refreshed runnable task examples/docs to prefer direct `enqueue(...)` and
  `enqueueAndWait(...)` with named overrides over `prepareEnqueue(...)` when
  no incremental builder assembly is needed.
- Refreshed workflow examples/docs to prefer direct `start(...)` named
  overrides over `prepareStart(...)` when no incremental builder assembly is
  needed.
- Clarified docs so direct `start(...)` / `startAndWait(...)` and
  `enqueue(...)` / `enqueueAndWait(...)` are the default happy path, with
  `buildStart(...)` and `buildCall(...)` positioned as the explicit advanced
  transport path.
- Removed the caller/context `prepareStart(...)` and `prepareEnqueue(...)`
  wrapper entrypoints so the explicit transport path now hangs directly off
  `WorkflowRef` and `TaskDefinition`.
- Clarified docs so `TaskCall` and `WorkflowStartCall` are described as the
  explicit low-level transport path, not peer happy-path APIs beside direct
  `enqueue(...)` / `start(...)` helpers.
- Added direct `buildCall(...)` / `buildStart(...)` helpers on task/workflow
  definitions so the explicit transport path no longer requires
  `prepare...().build()` when all overrides are already known.
- Removed `TaskCall.copyWith(...)` and `WorkflowStartCall.copyWith(...)`.
  Explicit transport objects are now built with their final overrides up
  front rather than mutated after construction.
- Added versioned manual-result convenience constructors:
  `TaskDefinition.noArgsVersionedJson(...)`,
  `WorkflowDefinition.flowVersionedJson(...)`,
  `WorkflowDefinition.scriptVersionedJson(...)`,
  `Flow.versionedJson(...)`, and `WorkflowScript.versionedJson(...)`.
- Removed no-args `buildCall()` / `buildStart()` transport wrappers in favor
  of the explicit typed surfaces:
  `definition.asDefinition.buildCall(())` and
  `ref0().asRef.buildStart(params: ())`.
- Removed `WorkflowRef.prepareStart(...)` and `WorkflowStartBuilder`; the
  explicit workflow transport path now uses `buildStart(...)` plus
  `copyWith(...)` when advanced overrides are needed.
- Removed `TaskDefinition.prepareEnqueue(...)` and `TaskEnqueueBuilder`; the
  explicit task transport path now uses `buildCall(...)` plus `copyWith(...)`
  when advanced overrides are needed.
- Added `QueueCustomEvent.metaJson(...)`, `metaVersionedJson(...)`, and
  `metaAs(codec: ...)` so queue-event metadata can decode DTO payloads
  without raw map casts.
- Added `TaskStatus.metaJson(...)`, `metaVersionedJson(...)`, and
  `metaAs(codec: ...)` so low-level task status metadata can decode DTO
  payloads without raw map casts.
- Added `WorkflowWatcher.dataJson(...)`, `dataVersionedJson(...)`,
  `dataAs(codec: ...)`, and the matching `WorkflowWatcherResolution`
  `resumeData...` helpers so watcher inspection can decode full stored watcher
  metadata DTOs without raw map casts.
- Added `RunState.paramsJson(...)`, `paramsVersionedJson(...)`, and
  `paramsAs(codec: ...)` so low-level workflow run snapshots can decode
  stored workflow input DTOs without raw map casts.
- Added `TaskError.metaJson(...)`, `metaVersionedJson(...)`, and
  `metaAs(codec: ...)` so low-level task failure metadata can decode DTO
  payloads without raw map casts.
- Added `WorkflowRunView.paramsJson(...)`,
  `paramsVersionedJson(...)`, and `paramsAs(codec: ...)` so workflow detail
  views can decode stored workflow input DTOs without raw map casts.
- Added `RunState.lastErrorJson(...)`, `runtimeJson(...)`,
  `cancellationDataJson(...)`, and the matching `WorkflowRunView` helpers so
  workflow inspection surfaces can decode error, runtime, and cancellation
  DTOs without raw map casts.
- Added `WorkerHeartbeat.extrasJson(...)`,
  `extrasVersionedJson(...)`, and `extrasAs(codec: ...)` so persisted worker
  heartbeat metadata can decode DTO payloads without raw map casts.
- Added `DeadLetterEntry.metaJson(...)`, `metaVersionedJson(...)`,
  `ScheduleEntry.argsJson(...)`, `kwargsJson(...)`, and `metaJson(...)` so
  DLQ and scheduler tooling can decode persisted DTO payloads without raw map
  casts.
- Added `ControlCommandMessage.payloadJson(...)`,
  `payloadVersionedJson(...)`, and the matching `ControlReplyMessage`
  payload/error helpers so low-level worker control tooling can decode DTO
  payloads without raw map casts.
- Added `WorkflowStepEvent.metadataJson(...)`,
  `metadataVersionedJson(...)`, `metadataPayloadJson(...)`, and the matching
  `WorkflowRuntimeEvent` helpers so workflow introspection metadata can decode
  DTOs without raw map casts.
- Added `WorkerEvent.dataJson(...)`, `dataVersionedJson(...)`, and
  `dataAs(codec: ...)` so worker observability events can decode structured
  event data without raw map casts.
- Added `ControlCommandCompletedPayload.responseJson(...)`,
  `responseVersionedJson(...)`, `responseAs(codec: ...)`, `errorJson(...)`,
  `errorVersionedJson(...)`, and `errorAs(codec: ...)` so control command
  result signals can decode structured response and error payloads without
  raw map plumbing.
- Added `TaskExecutionContext.argsAs(...)`, `argsJson(...)`,
  `argsVersionedJson(...)`, `WorkflowExecutionContext.paramsAs(...)`,
  `paramsJson(...)`, `paramsVersionedJson(...)`, and the same full-payload
  helpers on `WorkflowScriptContext`, so manual task/workflow code can decode
  an entire DTO input without field-by-field map plumbing.
- Added `argVersionedJson(...)`, `argListVersionedJson(...)`,
  `paramVersionedJson(...)`, and `paramListVersionedJson(...)` on the shared
  task/workflow context helpers so nested versioned DTO fields no longer
  require dropping down to raw payload-map helpers.
- Added `PayloadCodec.versionedJson(...)` so DTO payload codecs can persist a
  schema version beside the JSON payload and decode older shapes explicitly.
- Added `PayloadCodec.versionedMap(...)` for versioned DTO payloads that still
  need a custom map encoder or a nonstandard version-aware decode shape.
- Added `TaskEnqueuer.enqueueValue(...)` across producers and task/workflow
  execution contexts so dynamic task names can still enqueue typed DTO payloads
  through an explicit `PayloadCodec<T>` without hand-built arg maps.
- Added `WorkflowRuntime.startWorkflowValue(...)` and
  `StemWorkflowApp.startWorkflowValue(...)` so dynamic workflow names can start
  typed DTO-backed runs through an explicit `PayloadCodec<T>` without
  hand-built param maps.
- Added `QueueEventsProducer.emitValue(...)` so queue-scoped custom events can
  publish typed payloads through an explicit `PayloadCodec<T>` without
  hand-built maps.
- Added versioned low-level DTO shortcuts:
  `TaskEnqueuer.enqueueVersionedJson(...)`,
  `WorkflowRuntime.startWorkflowVersionedJson(...)`,
  `StemWorkflowApp.startWorkflowVersionedJson(...)`,
  `WorkflowRuntime.emitVersionedJson(...)`,
  `StemWorkflowApp.emitVersionedJson(...)`, and
  `QueueEventsProducer.emitVersionedJson(...)`.
- Added versioned workflow resume/result decode helpers:
  `WorkflowExecutionContext.previousVersionedJson(...)`,
  `WorkflowResumeContext.takeResumeVersionedJson(...)`,
  `waitForEventValueVersionedJson(...)`, and
  `waitForEventVersionedJson(...)`.
- Added `decodeVersionedJson:` to the low-level
  `Stem.waitForTask<T>`, `StemApp.waitForTask<T>`,
  `StemClient.waitForTask<T>`, `StemWorkflowApp.waitForCompletion<T>`, and
  `WorkflowRuntime.waitForCompletion<T>` APIs so schema-versioned DTO waits no
  longer need a manual raw-payload closure.
- Added direct `versionedJson(...)` shortcuts for manual task definitions,
  workflow refs, and workflow event refs so evolving DTO payloads do not need
  a separate `PayloadCodec.versionedJson(...)` constant in the common case.
- Added versioned DTO decode helpers across low-level result snapshots:
  `TaskStatus.payloadVersionedJson(...)`, `TaskResult.payloadVersionedJson(...)`,
  `WorkflowResult.payloadVersionedJson(...)`, `GroupStatus.resultVersionedJson(...)`,
  `RunState.resultVersionedJson(...)`, and
  `RunState.suspensionPayloadVersionedJson(...)`.
- Added low-level DTO shortcuts for name-based dispatch:
  `WorkflowRuntime.startWorkflowJson(...)`,
  `StemWorkflowApp.startWorkflowJson(...)`, `WorkflowRuntime.emitJson(...)`,
  and `StemWorkflowApp.emitJson(...)`, so dynamic workflow names and
  workflow-event topics can still use `toJson()` inputs without hand-built
  maps.
- Added `QueueEventsProducer.emitJson(...)` so queue-scoped custom events can
  publish DTO payloads without hand-built maps.
- Added `QueueCustomEvent.payloadValue(...)`,
  `payloadValueOr(...)`, and `requiredPayloadValue(...)` so queue-event
  consumers can decode typed payload fields without raw `payload['key']`
  casts.
- Added `QueueCustomEvent.payloadJson(...)`,
  `payloadVersionedJson(...)`, and `payloadAs(codec: ...)` so queue-event
  consumers can decode whole DTO payloads without rebuilding them field by
  field.
- Added `decodeJson:` shortcuts to the low-level
  `Stem.waitForTask<T>` and `StemWorkflowApp.waitForCompletion<T>` wait APIs,
  and propagated the same task wait shortcut through `StemApp` and
  `StemClient`, so DTO waits no longer need manual
  `payload as Map<String, Object?>` closures.
- Added typed task/workflow result readers:
  `TaskStatus.payloadValue(...)`, `payloadValueOr(...)`,
  `requiredPayloadValue(...)`, `TaskResult.valueOr(...)`,
  `TaskResult.requiredValue()`, `WorkflowResult.valueOr(...)`, and
  `WorkflowResult.requiredValue()` so low-level status reads and typed waits no
  longer need manual nullable handling or raw payload casts.
- Added `TaskStatus.payloadJson(...)` and `payloadAs(codec: ...)` so existing
  raw task-status reads can decode whole DTO payloads without another
  cast/closure.
- Added `TaskResult.payloadJson(...)` and `payloadAs(codec: ...)` so raw typed
  task-wait results can decode whole DTO payloads without another
  cast/closure.
- Added `WorkflowResult.payloadJson(...)` and `payloadAs(codec: ...)` so raw
  workflow completion results can decode whole DTO payloads without another
  cast/closure.
- Added `RunState.resultJson(...)`, `resultAs(codec: ...)`,
  `suspensionPayloadJson(...)`, and `suspensionPayloadAs(codec: ...)` so raw
  workflow-store inspection paths can decode DTO payloads without manual
  casts.
- Added `WorkflowWatcher.payloadJson(...)`, `payloadAs(codec: ...)`,
  `WorkflowWatcherResolution.payloadJson(...)`, `payloadAs(codec: ...)`, and
  `WorkflowStepEntry.valueJson(...)` / `valueAs(codec: ...)` so raw watcher
  and checkpoint inspection paths can decode DTO payloads without manual
  casts.
- Added `WorkflowRunView.resultJson(...)`,
  `WorkflowRunView.resultVersionedJson(...)`,
  `WorkflowRunView.suspensionPayloadJson(...)`,
  `WorkflowRunView.suspensionPayloadVersionedJson(...)`, and
  `WorkflowCheckpointView.valueJson(...)` /
  `valueVersionedJson(...)` plus their `...As(codec: ...)` counterparts so
  dashboard/CLI workflow detail views can decode DTO payloads without manual
  casts.
- Added `WorkflowStepEvent.resultJson(...)`,
  `resultVersionedJson(...)`, and `resultAs(codec: ...)` so workflow
  introspection consumers can decode DTO checkpoint results without manual
  casts.
- Added `TaskPostrunPayload.resultJson(...)`,
  `resultVersionedJson(...)`, and `resultAs(codec: ...)` so task lifecycle
  signal consumers can decode DTO task results without manual casts.
- Added `TaskSuccessPayload.resultJson(...)`,
  `resultVersionedJson(...)`, and `resultAs(codec: ...)` so success-only
  task signal consumers can decode DTO task results without manual casts.
- Added `WorkflowRunPayload.metadataValue(...)`,
  `requiredMetadataValue(...)`, `metadataJson(...)`, and
  `metadataAs(codec: ...)` so workflow lifecycle signal consumers can decode
  structured metadata without raw map casts.
- Added `WorkflowRunPayload.metadataPayloadJson(...)`,
  `metadataPayloadVersionedJson(...)`, and `metadataPayloadAs(codec: ...)` so
  workflow lifecycle signal consumers can decode a whole metadata DTO without
  field-by-field reads.
- Added `ProgressSignal.dataValue(...)`, `requiredDataValue(...)`,
  `dataJson(...)`, and `dataAs(codec: ...)` so raw task-progress signal
  consumers can decode structured progress metadata without raw map casts.
- Added `ProgressSignal.payloadJson(...)`,
  `payloadVersionedJson(...)`, and `payloadAs(codec: ...)` so raw task
  progress inspection can decode a whole DTO payload without field-by-field
  map reads.
- Added `TaskExecutionContext` as the shared task-side execution surface for
  `TaskContext` and `TaskInvocationContext`, and taught `stem_builder` to
  accept it directly in annotated task definitions.
- Added `TaskExecutionContext.retry(...)` so typed task handlers can request
  retries through the shared task context surface instead of depending on
  concrete runtime classes.
- Added `TaskExecutionContext.spawn(...)` so the shared task context surface
  now covers the common follow-up enqueue alias, including `notBefore`
  forwarding.
- Updated task docs/snippets to prefer `TaskExecutionContext` for shared
  enqueue/workflow/event examples, leaving `TaskContext` and
  `TaskInvocationContext` only where the runtime distinction matters.
- Added `FlowStepControl.dataJson(...)`, `dataVersionedJson(...)`, and
  `dataAs(codec: ...)` so lower-level suspension control objects can decode
  DTO metadata without manual casts.
- Added `GroupStatus.resultValues<T>()`, `resultJson(...)`, and
  `resultAs(codec: ...)` so canvas/group status inspection can decode typed
  child results without manually mapping raw `TaskStatus.payload` values.
- Added `arg<T>()`, `argOr<T>()`, and `requiredArg<T>()` on `TaskContext` and
  `TaskInvocationContext`, and taught both contexts to retain the current
  task args so manual handlers and isolate entrypoints can read typed inputs
  without threading raw `args[...]` lookups through their logic.
- Added `param<T>()`, `paramOr<T>()`, and `requiredParam<T>()` on
  `WorkflowExecutionContext` and `WorkflowScriptContext` so manual flows,
  checkpoints, and script run methods can read typed workflow start params
  without repeating `ctx.params[...]` lookups.
- Added `previousValue<T>()` and `requiredPreviousValue<T>()` on
  `WorkflowExecutionContext` so manual flow steps and script checkpoints can
  read prior persisted values without repeating raw `previousResult as ...`
  casts.
- Added typed payload-map readers like `args.requiredValue(...)`,
  `args.valueOr(...)`, and `ctx.params.requiredValue(...)` so manual tasks and
  workflows can decode scalars and codec-backed DTOs without repeating raw map
  casts.
- Added direct JSON entry readers like `args.requiredValueJson(...)`,
  `ctx.requiredParamJson(...)`, and shared `valueJson(...)` /
  `requiredValueJson(...)` helpers so nested DTO payload fields no longer need
  a separate `PayloadCodec<T>` constant.
- Added `Envelope.argsJson(...)`, `argsVersionedJson(...)`, `metaJson(...)`,
  and `metaVersionedJson(...)` so low-level producer and signal code can
  decode whole envelope DTO payloads without dropping to raw maps.
- Added typed DTO readers on isolate bridge payloads like
  `TaskEnqueueRequest.argsVersionedJson(...)`,
  `StartWorkflowRequest.paramsVersionedJson(...)`,
  `WaitForWorkflowResponse.resultVersionedJson(...)`, and
  `EmitWorkflowEventRequest.payloadVersionedJson(...)` so low-level
  cross-isolate helpers no longer need manual map casts.
- Added `valueVersionedJson(...)`, `requiredValueVersionedJson(...)`,
  `valueListVersionedJson(...)`, and
  `requiredValueListVersionedJson(...)` to the shared payload-map helpers so
  nested versioned DTO payloads no longer need custom per-surface decode
  plumbing.
- Added `previousJson(...)`, `requiredPreviousJson(...)`,
  `takeResumeJson(...)`, `waitForEventValueJson(...)`, and
  `waitForEventJson(...)` so workflow steps and checkpoints can decode prior
  DTO results and resume/event payloads without separate codec constants.
- Added `valueListJson(...)`, `requiredValueListJson(...)`,
  `argListJson(...)`, and `paramListJson(...)` so nested DTO lists can be
  decoded directly from durable payload maps without separate codec constants
  or manual list mapping.
- Added `TaskContext.progressJson(...)` and
  `TaskInvocationContext.progressJson(...)` so task progress updates can emit
  DTO payloads without hand-built maps.
- Added `TaskExecutionContext.progressVersionedJson(...)` so task progress
  updates can persist an explicit DTO schema version alongside the payload.
- Added `sleepJson(...)`, `sleepVersionedJson(...)`,
  `awaitEventJson(...)`, `awaitEventVersionedJson(...)`, and
  `FlowStepControl.awaitTopicJson(...)` so lower-level flow/script suspension
  directives can carry DTO metadata without hand-built maps.
- Added `valueList<T>()`, `valueListOr(...)`, and `requiredValueList(...)` to
  the shared payload-map helpers so canvas chains/chords and other meta-driven
  paths can decode typed list payloads without manual list casts.
- Added `WorkflowExecutionContext` as the shared typed execution context for
  flow steps and script checkpoints, and taught `stem_builder` to accept that
  shared context type directly in annotated workflow methods.
- Added `WorkflowRunPayload.metadataVersionedJson(...)` and
  `ProgressSignal.dataVersionedJson(...)` so signal payloads can decode
  versioned DTO metadata without manual casts.
- Simplified the manual JSON helper path so `TaskDefinition.json(...)` and
  `WorkflowRef.json(...)` no longer require unused producer-side
  `decodeArgs`/`decodeParams` callbacks just to publish DTO payloads.
- Added `WorkflowResumeContext` as the shared typed suspension/wait surface for
  flow steps and script checkpoints. Typed workflow event waits now target that
  shared interface instead of accepting an erased `Object`.
- Added `TaskDefinition.noArgsCodec(...)`, `Flow.codec(...)`,
  `WorkflowScript.codec(...)`, `WorkflowDefinition.flowCodec(...)`, and
  `.scriptCodec(...)` so the manual result path now has direct custom-codec
  helpers alongside the newer JSON shortcuts.
- Added `WorkflowDefinition.flowJson(...)` and
  `WorkflowDefinition.scriptJson(...)` so the raw definition path has the same
  direct DTO-result helper as `Flow.json(...)` and `WorkflowScript.json(...)`.
- Added `TaskDefinition.noArgsJson(...)`, `Flow.json(...)`, and
  `WorkflowScript.json(...)` as the shortest manual DTO result helpers for the
  common `toJson()` / `Type.fromJson(...)` path.
- Relaxed manual `Flow(...)`, `WorkflowScript(...)`, and
  `WorkflowDefinition.flow(...)` / `.script(...)` `decodeResultJson:` helpers
  to accept `Map<String, dynamic>` DTO decoders, matching the newer
  `PayloadCodec.json(...)` and `refJson(...)` surfaces.
- Renamed the caller-bound advanced child-workflow helpers from
  `prepareWorkflowStart(...)` / `prepareNoArgsWorkflowStart(...)` to
  `prepareStart(...)` so the caller side aligns with task-side
  `prepareEnqueue(...)` and ref-side `prepareStart(...)`.
- Renamed the advanced workflow-ref builder entrypoints from `startBuilder(...)`
  / `startBuilder()` to `prepareStart(...)` on `WorkflowRef` and
  `NoArgsWorkflowRef` so the workflow side aligns with task-side
  `prepareEnqueue(...)`.
- Relaxed JSON/codec DTO decoding helpers to accept `Map<String, dynamic>`
  `fromJson(...)` signatures across manual task/workflow/event helpers and the
  shared `PayloadCodec` surface. DTO payloads still persist as string-keyed
  JSON-like maps.
- Removed the deprecated workflow-event compatibility helpers:
  `emitWith(...)`, `emitEventBuilder(...)`, `waitForEventRef(...)`,
  `waitForEventRefValue(...)`, `awaitEventRef(...)`, `waitValueWith(...)`, and
  `waitWith(...)`. The direct `event.emit(...)`, `event.wait(...)`,
  `event.waitValue(...)`, and `event.awaitOn(...)` surfaces are now the only
  supported forms.
- Removed the deprecated workflow-start compatibility helpers:
  `startWith(...)`, `startAndWaitWith(...)`, `startWorkflowBuilder(...)`, and
  `startNoArgsWorkflowBuilder(...)`. The direct `start(...)`,
  `startAndWait(...)`, and `prepareWorkflowStart(...)` forms are now the only
  supported workflow-start surfaces.
- Removed the deprecated task-builder compatibility helpers:
  `enqueueBuilder(...)` and `enqueueNoArgsBuilder(...)`. The direct
  `prepareEnqueue(...)` form is now the only supported builder entrypoint.
- Removed the deprecated `withJsonCodec(...)` / `refWithJsonCodec(...)`
  compatibility helpers. The direct `json(...)` / `refJson(...)` forms are now
  the only supported JSON shortcut APIs.
- Removed the legacy `SimpleTaskRegistry` compatibility alias. Use
  `InMemoryTaskRegistry` directly.
- Replaced the older manual DTO helper names with direct forms:
  `TaskDefinition.json(...)`, `TaskDefinition.codec(...)`,
  `WorkflowRef.json(...)`, `WorkflowRef.codec(...)`, `refJson(...)`, and
  `refCodec(...)`.
- Added `prepareEnqueue(...)` as the clearer task-side name for advanced
  enqueue builders, and deprecated the older `enqueueBuilder(...)` /
  `enqueueNoArgsBuilder(...)` aliases.
- Added `prepareWorkflowStart(...)` / `prepareNoArgsWorkflowStart(...)` as the
  clearer names for caller-bound workflow start builders, and deprecated the
  older `startWorkflowBuilder(...)` / `startNoArgsWorkflowBuilder(...)`
  aliases.
- Added `event.awaitOn(step)` for the low-level flow-control event wait path,
  and deprecated `FlowContext.awaitEventRef(...)`.
- Deprecated script-step `awaitEventRef(...)` in favor of `await event.wait(ctx)`.
- Deprecated context-side `waitForEventRef(...)` and
  `waitForEventRefValue(...)` in favor of `event.waitValue(ctx)` and
  `event.wait(ctx)`.
- Deprecated `emitEventBuilder(...)` in favor of direct typed event calls via
  `event.emit(...)`.
- Deprecated the older workflow-start `startWith(...)` and
  `startAndWaitWith(...)` helpers in favor of direct `start(...)` and
  `startAndWait(...)` aliases.
- Deprecated the older workflow-event `emitWith(...)`, `waitWith(...)`, and
  `waitValueWith(...)` helpers in favor of the direct `emit(...)`, `wait(...)`,
  and `waitValue(...)` aliases.
- Added direct workflow-event aliases `event.emit(...)`, `event.wait(...)`,
  and `event.waitValue(...)`, while keeping the older `...With(...)` forms for
  compatibility.
- Refreshed the cancellation-policy workflow example to use the fluent builder
  `start(...)` alias instead of `startWith(...)`.
- Refreshed the remaining simple workflow examples to use direct `start(...)`
  aliases instead of `startWith(...)` where no advanced overrides are needed.
- Refreshed child-workflow examples and docs to prefer the direct
  `startAndWait(...)` alias over `startAndWaitWith(...)` in the common case.
- Refreshed the public workflow examples and docs snippets to prefer the direct
  `start(...)` alias over the older `startWith(...)` helper in the happy path.
- Added `StemApp.registerTask(...)`, `registerTasks(...)`, `registerModule(...)`,
  and `registerModules(...)` so plain task apps now have the same late
  registration ergonomics as `StemWorkflowApp`.
- Added `decodeResultJson:` support to manual `refWithJsonCodec(...)` helpers
  on `WorkflowDefinition`, `Flow`, and `WorkflowScript`, so DTO result
  decoding can now live entirely on the typed workflow ref path.
- Added named workflow start aliases `start(...)` and `startAndWait(...)` on
  workflow refs, no-args workflow refs, manual `Flow` / `WorkflowScript`
  wrappers, and workflow start calls/builders. The existing
  `startWith(...)` / `startAndWaitWith(...)` helpers still work.
- Added `StemModule.requiredTaskQueues()` and
  `StemModule.requiredWorkflowQueues(...)` so bundle queue requirements can be
  inspected directly before app/worker bootstrap.
- Added `StemModule.requiredTaskSubscription()` and
  `StemModule.requiredWorkflowSubscription(...)` so low-level worker wiring can
  reuse the exact subscription implied by a module without rebuilding it by
  hand.
- Added `decodeResultJson:` shortcuts on manual `Flow`, `WorkflowScript`, and
  `TaskDefinition.noArgs(...)` definitions so common DTO result decoding no
  longer needs a separate `PayloadCodec<T>.json(...)` constant.
- Added `TaskDefinition.withJsonCodec(...)`, `refWithJsonCodec(...)`, and
  `WorkflowEventRef<T>.json(...)` so manual DTO-backed tasks, workflows, and
  typed workflow events no longer need a separate codec constant in the common
  `toJson()` / `Type.fromJson(...)` case.
- Added `PayloadCodec<T>.json(...)` as the shortest DTO helper for types that
  already expose `toJson()` and `Type.fromJson(...)`, while keeping
  `PayloadCodec<T>.map(...)` for custom map encoders.
- Added `PayloadCodec<T>.map(...)` so map-shaped workflow/task DTO codecs no
  longer need handwritten `Object?` decode wrappers, and refreshed the public
  typed payload docs/examples around the new helper.
- Added expression-style workflow suspension helpers with named arguments:
  `await ctx.sleepFor(duration: ...)`,
  `await ctx.waitForEvent(topic: ...)`, and
  `await ctx.waitForEventRefValue(event: ...)` for both flow steps and script
  checkpoints.
- Added direct typed workflow event wait helpers:
  `await event.waitWith(ctx)` and `event.waitValueWith(ctx)` so typed workflow
  events now stay on the ref surface for both emit and wait paths.
- Added `StemModule.combine(...)` plus `modules:` support across `StemApp`,
  `StemWorkflowApp`, and `StemClient` bootstrap helpers so multi-module apps
  no longer need to pre-merge bundles manually at every call site.
- Added `registerModules(...)` on `StemWorkflowApp` so late registration can
  attach multiple generated or hand-written bundles with the same conflict
  rules as `StemModule.merge(...)`.
- Added `StemModule.merge(...)` so generated and hand-written bundles can be
  composed with fail-fast conflict checks instead of manual list stitching.
- Updated the public workflow event examples and docs to prefer the direct
  typed ref helper `event.emitWith(emitter, value)` for simple event emission,
  leaving bound event builders and prebuilt calls as lower-level variants.
- Updated the remaining README child-workflow snippet to use the direct
  no-args helper `childWorkflow.startAndWaitWith(context)` instead of an
  unnecessary `startBuilder()` hop.
- Updated the public workflow docs and annotated workflow example to prefer
  direct child-workflow helpers like `ref.startAndWaitWith(context, value)` in
  durable boundaries, keeping `startWorkflowBuilder(...)` for advanced
  override cases.
- Clarified the workflow docs so direct workflow helpers and generated refs are
  the default path, while `startWorkflow(...)` / `waitForCompletion(...)` are
  explicitly documented as the low-level name-driven APIs.
- Added `WorkflowCaller.startWorkflowBuilder(...)` /
  `startNoArgsWorkflowBuilder(...)` plus a caller-bound fluent builder so
  workflow-capable contexts, apps, and runtimes can start child workflows with
  the same builder-first ergonomics already used for typed task enqueue.
- Added `WorkflowEventEmitter.emitEventBuilder(...)` plus a caller-bound typed
  event call so apps, runtimes, and task/workflow contexts can emit typed
  workflow events without bouncing between emitter-first and ref-first styles.
- Added `TaskEnqueuer.enqueueBuilder(...)` / `enqueueNoArgsBuilder(...)` plus a
  caller-bound fluent task builder so producers and contexts can enqueue typed
  task calls directly from the enqueuer surface, with `enqueueAndWait()`
  available whenever that enqueuer also supports typed result waits.
- Updated the public workflow event examples and docs to prefer
  `emitEventBuilder(...).emit()` as the primary typed event emission path,
  while keeping the older `emitWith(...)` variants documented as lower-level
  alternatives.
- Updated the public no-input task examples to prefer
  `TaskDefinition.noArgs(...)` plus typed `enqueue()` / `enqueueAndWait()`
  helpers instead of reintroducing raw task-name strings in the happy path.
- Added `TaskDefinition.enqueueBuilder(...)` /
  `NoArgsTaskDefinition.enqueueBuilder()` so typed tasks now expose the same
  definition-first fluent builder pattern as typed workflow refs.
- Added direct no-args `startWith(...)`, `startAndWaitWith(...)`,
  `startBuilder()`, and `waitFor(...)` helpers on manual `Flow` and
  `WorkflowScript` definitions so simple workflows no longer need an extra
  `ref0()` hop just to start or wait.
- Updated the public typed task examples to prefer `enqueueAndWait(...)` as the
  happy path when callers only need the final typed result, while keeping
  `waitFor(...)` documented for task-id-driven inspection flows.
- Updated the remaining no-args workflow examples and docs snippets to use the
  new direct `Flow.startWith(...)` / `Flow.waitFor(...)` helpers instead of
  creating a temporary `ref0()` only to start and wait.
- Updated the remaining no-input producer examples to prefer
  `TaskDefinition.noArgs(...)` over raw empty-map publishes where the task
  already has a stable typed definition.
- Updated the persistence and signals docs snippets to use the same no-input
  task-definition helpers instead of raw empty-map enqueue calls.
- Updated the manual child-workflow docs to prefer
  `childFlow.startBuilder().startAndWaitWith(context)` over creating a
  temporary `ref0()` only to start a no-args child run.
- Made `TaskContext` and `TaskInvocationContext` implement
  `WorkflowEventEmitter` when a workflow runtime is attached, so inline
  handlers and isolate entrypoints can resume waiting workflows with
  `emitValue(...)` or typed `WorkflowEventRef<T>`.
- Made `TaskContext` and `TaskInvocationContext` implement
  `WorkflowCaller` when a workflow runtime is attached, so inline handlers and
  isolate entrypoints can start and wait for typed child workflows directly.
- Added `awaitEventRef(...)` on flow and script checkpoint resume helpers so
  typed `WorkflowEventRef<T>` values now cover both the common wait-for-value
  path and the lower-level suspend-first path.
- Reframed the producer docs to treat `TaskDefinition` and shared
  `TaskEnqueuer` surfaces as the happy path, keeping raw name-based enqueue as
  the lower-level interop option.
- Tightened advanced builder dispatch so `TaskEnqueueBuilder` and
  `WorkflowStartBuilder` now only build `TaskCall` / `WorkflowStartCall`
  values; dispatch goes through direct `enqueue(...)` / `start(...)` helpers
  or explicit `enqueueCall(...)` / `startWorkflowCall(...)`.
- Added direct typed workflow event helper APIs so event refs can emit
  payloads without repeating raw topic strings or separate codecs.
- Added `WorkflowStartBuilder` plus `WorkflowRef.startBuilder(...)` /
  `NoArgsWorkflowRef.startBuilder()` so typed workflow refs can fluently set
  `parentRunId`, `ttl`, and `WorkflowCancellationPolicy` without dropping to
  raw workflow-name APIs.
- Updated the public annotated workflow example and workflow docs to keep
  context-aware script workflows on the direct annotated checkpoint path,
  removing the redundant outer `script.step(...)` wrapper from the happy path.
- Made `StemApp` lazy-start its managed worker on first enqueue/wait and
  `app.canvas` dispatch calls so in-memory and module-backed task apps no
  longer need an explicit `start()` in the common case.
- Made `StemClient.createWorker(...)` infer queue subscriptions from bundled
  or explicitly supplied task handlers when `workerConfig.subscription` is
  omitted.
- Made raw `Stem.enqueue('task.name')` inherit handler-declared publish defaults
  like queue routing, priority, visibility timeout, and retry policy when the
  producer does not override them explicitly.
- Updated the public snippets and annotated workflow example to use the
  high-level app surfaces directly, dropping unnecessary `start()` calls and
  `app.stem` hops in the common in-memory and workflow happy paths.
- Updated the client-backed workflow examples to attach `stemModule` at
  `StemClient` creation time and then call `createWorkflowApp()` without
  repeating the bundle.
- Updated the `stack_autowire` example to use `StemApp` lazy-start and the
  high-level `app.enqueue(...)` / `app.waitForTask(...)` surface instead of
  manually starting the task app and dropping to `app.stem`.
- Updated the uniqueness snippet to show raw `app.enqueue(...)` inheriting
  handler-declared queue and uniqueness defaults, while still demonstrating
  explicit uniqueness-key overrides without manual worker startup.
- Simplified the `task_usage_patterns` example to use `StemApp.inMemory(...)`
  instead of manually wiring `Broker`, `Worker`, and `Stem` just to demonstrate
  typed task-definition enqueue and wait helpers.
- Simplified `example/stem_example.dart` and the getting-started docs that
  embed it to use `StemApp.fromUrl(...)` plus typed wait helpers instead of
  manually wiring broker/backend/worker instances.
- Simplified the Redis producer examples in `retry_task` and `signals_demo` to
  use `StemClient.fromUrl(...)` instead of manually creating a broker and raw
  `Stem` producer just to enqueue tasks.
- Simplified the TLS-aware `autoscaling_demo` and `ops_health_suite` producer
  examples to use `StemClient.create(...)` with broker/backend factories
  instead of hand-constructing `Stem` for publishing.
- Simplified the `worker_control_lab` and `progress_heartbeat` producer
  examples to use `StemClient.create(...)` with their existing connection
  helpers instead of manually wiring `Stem`.
- Added `notBefore` support to the shared `TaskEnqueuer` surface so
  `StemClient`, `StemApp`, workflow contexts, and task contexts can publish
  delayed tasks without dropping down to raw `Stem`.
- Updated the producer and programmatic-worker documentation snippets to use
  `StemApp`/`StemClient` for their producer examples, keeping low-level worker
  examples intact while reducing manual broker/backend wiring in the happy
  path.
- Simplified the Postgres-backed enqueuer examples (`postgres_worker`,
  `redis_postgres_worker`, and `postgres_tls`) to use `StemClient.create(...)`
  with explicit broker/backend factories instead of hand-constructing `Stem`
  for publishing.
- Simplified the `encrypted_payload`, `email_service`, and
  `signing_key_rotation` producer/enqueuer examples to use client-backed
  publishing instead of manually wiring `Stem` just to enqueue tasks.
- Simplified the `task_context_mixed` enqueue example to use
  `StemClient.create(...)` with its existing SQLite broker helper instead of
  manually creating a raw `Stem` producer for task submission.
- Simplified the `image_processor` HTTP API example to use
  `StemClient.create(...)` with Redis broker/result backend factories instead
  of manually constructing a raw `Stem` publisher service.
- Simplified the typed task-definition docs snippet to use
  `StemApp.inMemory(...)` and `definition.enqueueAndWait(...)` instead of
  manually wiring in-memory broker/backend instances and raw result waits.
- Simplified the `routing_parity` publisher example to use
  `StemClient.create(...)` with its explicit routing registry and Redis broker
  factory instead of manually constructing a raw `Stem` publisher.
- Simplified the best-practices docs snippet to use `StemApp.inMemory(...)`
  and a generic `TaskEnqueuer` helper instead of manually wiring `Stem` and
  `Worker` just to enqueue a single in-memory task.
- Simplified the `microservice/enqueuer` HTTP service to use
  `StemClient.create(...)` for publishing while keeping `Canvas` and the
  autofill controller on the client-owned broker/backend instances.
- Generalized the signing rotation docs snippet to target `TaskEnqueuer`
  instead of a concrete `Stem` producer so the example teaches the shared
  enqueue surface.
- Generalized the microservice enqueuer's autofill controller to target
  `TaskEnqueuer` instead of a concrete `Stem`, keeping the enqueue loop on the
  shared producer surface.
- Simplified the `encrypted_payload/docker` producer entrypoint to use
  `StemClient.create(...)` instead of manually constructing a raw `Stem`
  publisher inside the container example.
- Simplified the `rate_limit_delay` producer example to use
  `StemClient.create(...)` with its existing broker/backend helpers instead of
  building a raw `Stem` producer for the delayed enqueue loop.
- Simplified the `dlq_sandbox` producer example to use
  `StemClient.create(...)` with its existing broker/backend helpers instead of
  building a raw `Stem` producer for the dead-letter sandbox.
- Simplified the routing bootstrap docs snippet to use
  `StemClient.create(...)` and `createWorker(...)` instead of manually opening
  separate broker/backend pairs just to demonstrate routing subscription setup.
- Simplified the observability tracing docs snippet to use
  `StemClient.inMemory(...)` instead of manually wiring in-memory broker and
  backend instances for the traced producer path.
- Simplified the `otel_metrics` worker example to use
  `StemClient.inMemory(...)` and `createWorker(...)` so the producer-side ping
  loop no longer needs a raw `Stem` instance.
- Simplified the production signing checklist snippet to use
  `StemClient.create(...)` with in-memory factories and `createWorker(...)`,
  and updated the docs tab copy to describe the shared client setup instead of
  raw `Stem` wiring.
- Simplified the persistence backend docs snippets to use
  `StemClient.create(...)` while still showing the explicit in-memory, Redis,
  Postgres, and SQLite backend choices.
- Simplified the README Redis task examples to use `StemClient.fromUrl(...)`
  and `createWorker(...)` instead of manually wiring raw `Stem` and `Worker`
  instances in the happy path.
- Simplified the mixed-cluster enqueuer example to use `StemClient.create(...)`
  and normal client shutdown instead of returning raw `Stem` producers with
  manual adapter-specific close logic.
- Simplified the developer-environment bootstrap snippet to use a shared
  `StemClient` plus `createWorker(...)` while keeping the explicit Redis
  adapter configuration visible.
- Simplified the unique-task example to use `StemClient.create(...)` and
  `createWorker(...)` so the example stays focused on deduplication semantics
  instead of raw producer wiring.
- Simplified the README unique-task deduplication snippet to use
  `StemClient.create(...)` instead of a raw `Stem(...)` constructor example.
- Added `StemClient.createCanvas()` so shared-client setups can reuse the
  client-owned broker/backend/registry for canvas dispatch without manually
  constructing `Canvas(...)`.
- Added `getTaskStatus(...)` / `getGroupStatus(...)` to the shared
  `TaskResultCaller` surface so apps and clients can inspect task/group state
  without reaching into the raw result backend.
- Updated the developer environment and canvas docs to use the shared status
  helpers as the default status-inspection path, keeping raw backend reads as
  low-level guidance only.
- Simplified the `canvas_patterns` examples to use `StemApp.inMemory(...)`,
  `app.canvas`, and the shared task/group status helpers instead of manual
  broker/backend/worker wiring.
- Added `StemApp.createWorkflowApp(...)` and made `StemWorkflowApp.create(
  stemApp: ...)` reuse `stemApp.module` by default while failing fast when the
  reused worker does not actually cover the workflow/task queues the runtime
  needs.
- Made `Canvas.group(..., groupId: ...)` auto-initialize missing groups so
  custom group ids no longer require a manual `backend.initGroup(...)` first.
- Added `StemWorkflowApp.viewRunDetail(...)` so app-level workflow inspection
  no longer needs to reach through `workflowApp.runtime`.
- Added `StemWorkflowApp.executeRun(...)` so examples and app code can drive a
  workflow run directly without reaching through `workflowApp.runtime`.
- Added `StemWorkflowApp.viewRun(...)`, `viewCheckpoints(...)`, and
  `listRunViews(...)` so app-level workflow inspection can stay on the app
  surface instead of reaching through `workflowApp.runtime`.
- Added `StemWorkflowApp.workflowManifest()` so manifest inspection can stay on
  the app surface instead of reaching through `workflowApp.runtime`.
- Added `StemWorkflowApp.registerModule(...)` so manual builder/module
  registration no longer needs to reach through `app.runtime.registry` and
  `app.app.registry`.
- Added `StemWorkflowApp.registerWorkflow(...)` so manual workflow definition
  registration no longer needs to reach through `workflowApp.runtime`.
- Added `StemWorkflowApp.registerFlow(...)` and `registerScript(...)` so manual
  flow/script registration no longer needs to pass `.definition`.
- Added `StemWorkflowApp.registerWorkflows(...)` so manual bulk definition
  registration no longer needs repeated helper calls.
- Added `StemWorkflowApp.registerFlows(...)` and `registerScripts(...)` so
  manual bulk registration no longer needs repeated helper calls.
- Added `continuationQueue:` and `executionQueue:` to `StemWorkflowApp`
  bootstrap helpers so custom workflow channel wiring no longer needs manual
  `WorkflowRuntime` construction.
- Clarified the README workflow guidance to prefer `StemWorkflowApp`
  helpers in the happy path and reserve direct `WorkflowRuntime` usage for
  low-level scenarios.
- Refreshed workflow docs snippets to match the app-level workflow helper
  surface, including `resumeDueRuns(...)` guidance for fake-clock tests.
- Documented the new bulk registration helpers and custom workflow queue
  options in the README and workflow guide.
- Added `StemWorkflowApp.rewindToCheckpoint(...)` so replay-oriented flows no
  longer need to call `store.rewindToStep(...)` and `store.markRunning(...)`
  directly.
- Added `StemWorkflowApp.listWatchers(...)` so event-watcher inspection no
  longer needs to reach through `app.store`.
- Added `StemWorkflowApp.resumeDueRuns(...)` so sleep-based workflows no longer
  need to call `store.dueRuns(...)`, `store.get(...)`, and `store.markResumed(
  ...)` directly.
- Removed the remaining `client.stem` leak from the microservice enqueuer
  example and clarified in the README/docs that `FlowContext` and
  `WorkflowScriptStepContext` share the same child-workflow helper surface.
- Clarified in the worker-programmatic and signing docs that the remaining raw
  `Stem` examples are intentionally the lower-level embedding path, not the
  default happy path.
- Removed the now-unused raw `Stem` helper constructors from the DLQ sandbox
  and rate-limit delay shared libraries after those demos moved to
  `StemClient`-based producers.
- Flattened single-argument generated workflow/task refs and helper calls so
  one-field annotated workflows/tasks now use direct values instead of
  synthetic named-record wrappers in generated APIs, examples, and docs.
- Added `StemModule`, typed `WorkflowRef`/`WorkflowStartCall` helpers, and bundle-first `StemWorkflowApp`/`StemClient` composition for generated workflow and task definitions.
- Added `PayloadCodec`, typed workflow resume helpers, codec-backed workflow checkpoint/result persistence, typed task result waiting, and typed workflow event emit helpers for DTO-shaped payloads.
- Made `FlowContext` and `WorkflowScriptStepContext` implement `WorkflowCaller`
  directly so child workflows can start and wait through
  `WorkflowStartCall.startWith(...)` / `startAndWaitWith(...)` without special
  context-only helper variants.
- Removed the redundant `startWithContext(...)` /
  `startAndWaitWithContext(...)` workflow-ref helpers and the separate
  `WorkflowChildCallerContext` contract so child workflow starts consistently
  target the direct `WorkflowCaller` surface.
- Added `WorkflowEventEmitter` plus the unified `WorkflowEventRef.emitWith(...)`
  helper so typed workflow events no longer branch between app-specific and
  runtime-specific dispatch helpers.
- Removed the redundant app/runtime-specific workflow helper wrappers
  (`startWithApp`, `startWithRuntime`, `startAndWaitWithApp`,
  `startAndWaitWithRuntime`, `waitForWithRuntime`) so workflow refs and start
  calls consistently use the generic `startWith(...)`, `startAndWaitWith(...)`,
  and `waitFor(...)` surface.
- Simplified generated annotated task usage so `StemTaskDefinitions.*` is the
  canonical surface, reusing shared `TaskCall.enqueue(...)` and
  `TaskDefinition.waitFor(...)` helpers instead of emitting separate generated
  enqueue/wait extension APIs.
- Added `WorkflowStartCall.startWith(...)` so workflow refs can dispatch
  uniformly through apps, runtimes, and child-workflow callers instead of
  dropping back to `startWorkflowRef(...)` in durable workflow code.
- Added `Flow.ref(...)` / `WorkflowScript.ref(...)` helpers so manual workflow
  definitions can derive typed workflow refs without repeating workflow-name
  strings or manual result decoder wiring.
- Updated the manual workflow examples and docs to start runs through typed
  refs instead of repeating raw workflow-name strings in the happy path.
- Added `NoArgsWorkflowRef` plus `Flow.ref0()` / `WorkflowScript.ref0()` so
  zero-input workflows can start directly without passing `const {}`.
- Added workflow manifests, runtime metadata views, and run/step drilldown APIs
  for inspecting workflow definitions and persisted execution state.
- Clarified the workflow authoring model by distinguishing flow steps from
  script checkpoints in manifests, docs, dashboard wording, and generated
  workflow output.
- Improved workflow store contracts and runtime compatibility for caller-
  supplied run ids and persisted runtime metadata attached to workflow params.
- Restored the deprecated `SimpleTaskRegistry` alias for source compatibility
  and fixed workflow continuation routing to honor persisted queue metadata
  when resuming suspended runs after runtime configuration changes.
- Added `tasks:`-first wiring across `Stem`, `Worker`, `Canvas`, and
  `StemWorkflowApp`, removing the need for manual default-registry setup in
  normal application code and examples.
- Renamed the default in-memory task registry surface to
  `InMemoryTaskRegistry` and refreshed docs/examples to teach `tasks: [...]`
  rather than explicit registry construction.
- Improved workflow logging with richer run/step context on worker lifecycle
  lines plus enqueue/suspend/fail/complete runtime events.
- Exported logging types from `package:stem/stem.dart`, including `Level`,
  `Logger`, and `Context`.
- Added an end-to-end ecommerce workflow example using mixed annotated/manual
  workflows, `StemWorkflowApp`, and Ormed-backed SQLite models/migrations.
- Expanded span attribution across enqueue/consume/execute with task identity,
  queue, worker, host, lineage, namespace, and workflow step metadata
  (`run_id`, `step`, `step_id`, `step_index`, `step_attempt`, `iteration`).
- Improved worker retry republish behavior to preserve optional payload signing
  when retrying deliveries.
- Added workflow metadata quality-of-life getters and watcher/run-state helpers
  to make workflow introspection easier from task metadata.
- Strengthened tracing and workflow-related test coverage for metadata
  propagation and contract behavior.
- Expanded the microservice example with richer workload generation, queue
  diversity, updated scheduler/demo flows, and full local observability wiring
  for Jaeger/Prometheus/Grafana through nginx.
- Improved bootstrap DX with explicit fail-fast errors across broker/backend/
  workflow/schedule/lock/revoke resolution paths in `StemStack.fromUrl`,
  including actionable hints when adapters support a URL but do not implement
  the requested store kind.
- Refreshed docs to lead with `StemClient` and document adapter-focused Task
  workflows.
- Aligned in-memory broker and result backend semantics with shared adapter
  contracts, including broadcast fan-out behavior for in-memory broker tests.
- Added Taskfile support for package-scoped test orchestration.
- Added Taskfile-based workflows for complex examples (microservice, encrypted
  payloads, signing key rotation, security profiles, and Postgres TLS),
  including secret/certificate bootstrap and binary build/run helpers.
- Added shared logger injection via `setStemLogger` and reusable structured
  context helpers for consistent logging metadata across core components.

## 0.1.0

- Added workflow run leasing APIs (`claimRun`, `renewRunLease`, `releaseRun`,
  `listRunnableRuns`) and runtime ownership tracking to safely spread workflows
  across workers.
- Added TaskRetryPolicy and TaskEnqueueOptions for per-enqueue overrides
  (timing, retries, callbacks), plus TaskContext/TaskInvocationContext enqueue,
  spawn, and retry helpers including isolate entrypoint support and a fluent
  TaskEnqueueBuilder.
- Added inline FunctionTaskHandler execution (runInIsolate toggle) to simplify
  choosing between inline vs. isolate task execution.
- Added workflow/task annotations and a registry builder to streamline
  declarative workflow setup with existing Flow/WorkflowScript APIs.
- Added StemClient as a single entrypoint for configuring workers and workflow
  apps with shared broker/backend registries.
- Added TaskContext demos and refreshed docs/snippets for enqueue options and
  SQLite guidance.
- Added typed workflow, task, and canvas result APIs with customizable encoders
  (TaskResultEncoder and payload encoders).
- Added new example suites (progress heartbeat, worker control lab, and the
  feature-complete set) plus refreshed docs/Taskfiles for running them.
- Added signals registry/configuration for worker, task, scheduler, and
  workflow lifecycle events.
- Improved worker runtime (isolate pool, config, heartbeats/autoscaling) plus
  scheduler behavior (timezone alias handling, in-memory schedule store).
- Exposed lock ownership in interfaces and migrated IDs to UUID v7.
- Removed sqlite migrations from core and updated dependencies (collection,
  contextual, crypto, cryptography, timezone, uuid).
- Expanded internal docs and example suites, plus broader unit/property and
  workflow store contract coverage.

## 0.1.0-alpha.4

- Introduced **Durable Workflows** end-to-end: auto-versioned steps, iteration-
  aware contexts, and durable event watchers so long-running flows replay safely
  and resume with persisted payloads.
- Added a `WorkflowClock` abstraction (with `FakeWorkflowClock`) so runtimes and
  stores can record deterministic timestamps during testing.
- Refined sleep/await behaviour: persisted wake timestamps now prevent
  re-suspending once a delay has elapsed, and `saveStep` refreshes run heartbeats
  so active workers retain ownership.
- Updated all workflow stores to consume injected clock metadata, ensuring
  suspension payloads include `resumeAt`/`deadline` values without relying on
  `DateTime.now()`.
- Wired `TaskOptions.unique` into the runtime via the new
  `UniqueTaskCoordinator`, allowing clusters to deduplicate submissions using
  shared `LockStore`s and surface duplicate metadata when a clash occurs.
- Workers now coordinate chord callbacks through `ResultBackend.claimChord`,
  persisting callback ids and dispatch timestamps so fan-in callbacks run exactly
  once even after crashes or retry storms.

## 0.1.0-alpha.3

- Split Redis/Postgres adapters and CLI into dedicated packages (`stem_redis`,
  `stem_postgres`, `stem_cli`) so the core package only exposes platform-agnostic
  runtime APIs.
- Updated examples, docs, and integration guides to reference the new packages.

## 0.1.0-alpha.2

- Replace the legacy `opentelemetry` dependency with `dartastic_opentelemetry` and update tracing/metrics integrations.
- Add `_init_test_env` helper to start dockerised dependencies and export integration env vars.
- Refresh project docs to mention the new telemetry stack and test environment workflow.
- Bump direct dependencies (dartastic_opentelemetry 0.9.2, postgres 3.5.9, timezone 0.10.1) and align transitive packages.

## 0.1.0-alpha

- Initial version.
