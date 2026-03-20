# Changelog

## 0.1.1

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
- Added `WorkflowExecutionContext` as the shared typed execution context for
  flow steps and script checkpoints, and taught `stem_builder` to accept that
  shared context type directly in annotated workflow methods.
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
  `prepareStart(...)` / `prepareNoArgsStart(...)` so the caller side aligns
  with task-side `prepareEnqueue(...)` and ref-side `prepareStart(...)`.
- Renamed the advanced workflow-ref builder entrypoints from `startBuilder(...)`
  / `startBuilder()` to `prepareStart(...)` / `prepareStart()` on
  `WorkflowRef`, `NoArgsWorkflowRef`, `Flow`, and `WorkflowScript` so the
  workflow side aligns with task-side `prepareEnqueue(...)`.
- Relaxed JSON/codec DTO decoding helpers to accept `Map<String, dynamic>`
  `fromJson(...)` signatures across manual task/workflow/event helpers and the
  shared `PayloadCodec` surface. DTO payloads still persist as string-keyed
  JSON-like maps.
- Removed the deprecated workflow-event compatibility helpers:
  `emitWith(...)`, `emitEventBuilder(...)`, `waitForEventRef(...)`,
  `waitForEventRefValue(...)`, `awaitEventRef(...)`, `waitValueWith(...)`, and
  `waitWith(...)`. The direct `event.emit(...)`, `event.call(...).emit(...)`,
  `event.wait(...)`, `event.waitValue(...)`, and `event.awaitOn(...)` surfaces
  are now the only supported forms.
- Removed the deprecated workflow-start compatibility helpers:
  `startWith(...)`, `startAndWaitWith(...)`, `startWorkflowBuilder(...)`, and
  `startNoArgsWorkflowBuilder(...)`. The direct `start(...)`,
  `startAndWait(...)`, and `prepareWorkflowStart(...)` forms are now the only
  supported workflow-start surfaces.
- Removed the deprecated task-builder compatibility helpers:
  `enqueueBuilder(...)` and `enqueueNoArgsBuilder(...)`. The direct
  `prepareEnqueue(...)` and `prepareNoArgsEnqueue(...)` forms are now the only
  supported builder entrypoints.
- Removed the deprecated `withJsonCodec(...)` / `refWithJsonCodec(...)`
  compatibility helpers. The direct `json(...)` / `refJson(...)` forms are now
  the only supported JSON shortcut APIs.
- Removed the legacy `SimpleTaskRegistry` compatibility alias. Use
  `InMemoryTaskRegistry` directly.
- Replaced the older manual DTO helper names with direct forms:
  `TaskDefinition.json(...)`, `TaskDefinition.codec(...)`,
  `WorkflowRef.json(...)`, `WorkflowRef.codec(...)`, `refJson(...)`, and
  `refCodec(...)`.
- Added `prepareEnqueue(...)` / `prepareNoArgsEnqueue(...)` as the clearer
  task-side names for advanced enqueue builders, and deprecated the older
  `enqueueBuilder(...)` / `enqueueNoArgsBuilder(...)` aliases.
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
  `event.emit(...)` or `event.call(value).emit(...)`.
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
- Added `TaskEnqueueBuilder.enqueueAndWait(...)` so fluent per-call task
  overrides no longer require a separate manual wait step.
- Added `WorkflowEventRef.call(value)` plus `WorkflowEventCall.emitWith(...)`
  so typed workflow events now have the same prebuilt-call ergonomics as tasks
  and workflow starts.
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
  zero-input workflows can use `.call()` instead of passing `const {}`.
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
