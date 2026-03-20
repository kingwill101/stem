# Changelog

## 0.1.1

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
