# Changelog

## Unreleased

- Raised the ecommerce example's minimum Dart SDK to 3.10.0.

## 0.3.0

- Promoted the typed stable/advanced API boundary and removed implicit worker
  startup from producer, inspection, Canvas, and workflow operations.
- Added capability-aware queue transports, public cooperative cancellation,
  explicit task execution modes,
  typed rate limits, heterogeneous Canvas chains, explicit chord policies, and
  OpenTelemetry Canvas fan-out span links.
- Scheduler dispatch now revalidates distributed lock ownership immediately
  before publication and records lease-loss failures instead of publishing
  after ownership has expired.
- Added compatibility-safe fencing-token support to lock handles. Memory,
  Redis, and Postgres acquisitions expose monotonically increasing tokens;
  Beat propagates the token on scheduled envelopes for downstream enforcement.
- This release intentionally contains breaking API changes from the 0.2 line.
- The observability entrypoint now exposes Stem-owned logging types and a
  structured logging facade; the `contextual` logger types remain internal.
- Lease renewal derives its cadence from the remaining lease, so short
  visibility leases are renewed before expiry instead of being forced onto the
  default one-second minimum interval.
- Failed automatic renewals retry on a shorter cadence, and late in-flight
  renewals cannot recreate timers after a delivery has been cancelled.
- Active-delivery accounting uses worker-local delivery handles, so concurrent
  redeliveries of one envelope no longer overwrite shutdown or in-flight state.
- Lease timers are keyed by delivery identity rather than receipt text, which
  keeps same-receipt redeliveries independent for adapters that reuse row IDs.
- Automatic heartbeat timers now use the same delivery identity, preventing a
  concurrent redelivery from cancelling the original task's heartbeat.
- Lease renewal now remains active through terminal result persistence,
  group/chord bookkeeping, retry or dead-letter publication, linked-task
  dispatch, and acknowledgement; slow terminal handling cannot expire the
  delivery before the worker releases it.
- Lease renewal now starts when a delivery enters the worker, covering slow
  consume middleware, signature validation, backend lookups, and rate-limit
  decisions before handler execution.
- Concurrent redeliveries of an envelope already active in the same worker are
  acknowledged without a second handler invocation; process-wide failures
  still rely on normal at-least-once recovery.
- Documentation now distinguishes heartbeat/liveness signals from broker lease
  extension; use automatic renewal or `context.extendLease(...)` for leases.
- Added the optional `AtomicTerminalResultBackend` capability. Built-in result
  backends arbitrate terminal writes so a late cross-worker completion cannot
  replace the first terminal result; custom backends remain source compatible
  and retain their previous non-atomic fallback behavior.
- Worker terminal side effects such as group/chord bookkeeping, linked-task
  dispatch, terminal signals, and unique-lock release now belong only to the
  worker that wins terminal-result arbitration.
- Added a deterministic lease-loss recovery regression: renewal failure lets a
  delivery expire, a replacement worker can complete the redelivery, and the
  original late completion cannot overwrite that terminal result.
- Payload-decoding failures are now terminally failed and dead-lettered as
  `invalid-payload` instead of escaping before acknowledgement and redelivering
  indefinitely. Retry-storm coverage verifies that normal retry budgets remain
  bounded under concurrent failure.
- Hard-shutdown coverage now verifies that a full broker prefetch window is
  requeued and completed by a replacement worker, not only a single active
  isolate delivery.
- Added a warmed-up core throughput benchmark with a checked regression
  baseline and scheduled CI execution.

## 0.2.3

- Added additive `QueueBroker`, `LeaseBroker`, `InspectableBroker`, and
  `DeadLetterBroker` capability interfaces for new adapter integrations.
- Made managed worker startup explicit for every bootstrap path. Enqueue,
  status, result-wait, Canvas, and workflow operations never start a worker;
  applications must call `start()` (or `startWorker()`) deliberately.
- Added `stable.dart` and `advanced.dart` entrypoints to make the intended API
  boundary explicit while retaining the historical `stem.dart` compatibility
  barrel.
- Made `QueueBroker` independently implementable; lease, inspection, purge,
  and dead-letter operations are now optional capability interfaces with
  compatibility defaults on `Broker`.
- Extracted isolate execution and pool lifecycle into an internal execution
  supervisor, and hardened shutdown against late delivery errors after the
  worker event stream closes.
- Centralized worker event emission so late timers, retries, heartbeats,
  progress callbacks, and revocation notifications are safely ignored after
  shutdown.
- Extracted broker subscription ownership and stream error boundaries into an
  internal worker consumer loop, including safe queue-subscription replacement
  during pause and resume operations.

## 0.2.2

- Replaced string rate-limit fields with typed `RateLimit` values while
  retaining legacy parsing at JSON/configuration boundaries.
- Added cooperative task cancellation through
  `TaskExecutionContext.cancellation`.
- Made memory adapters available through the explicit
  `package:stem/memory.dart` library.
- Prevented status and result-wait operations from implicitly starting a
  worker.
- Moved release validation to dependency-ordered workspace automation and
  added aggregate package quality gates.
- Added a source-compatible `BrokerCapabilities` snapshot so adapters can
  declare optional delivery, inspection, broadcast, lease, and dead-letter
  behavior without expanding the base broker contract.
- Added queue-broker extension methods for optional dead-letter inspection,
  replay, and purge operations, allowing integrations to depend on
  `QueueBroker` without reverting to the legacy broad `Broker` type.

## 0.2.1

- Guarded worker and example process signal registration so Windows only
  installs supported shutdown watchers, avoiding unsupported `SIGTERM` /
  `SIGQUIT` subscriptions during graceful shutdown setup.

## 0.2.0

- Added `StemClient.fromStack(...)` and `StemStack.createClient(...)` so
  adapter-resolved broker/backend stacks have the same direct bootstrap path
  as the higher-level app helpers.
- Narrowed the public task and workflow invocation APIs around direct
  `enqueue(...)` / `enqueueAndWait(...)` and `start(...)` / `startAndWait(...)`
  calls, with explicit transport objects left as the advanced low-level path.
- Removed duplicate transport helpers and wrapper builder entrypoints such as
  `.call(...)`, `prepareStart(...)`, `prepareEnqueue(...)`, builder dispatch
  methods, and `copyWith(...)` on transport objects.
- Added shared execution-context interfaces for workflows and tasks so manual
  handlers and checkpoints can use one typed context surface instead of several
  partially overlapping ones.
- Added expression-style suspension and event APIs for workflows, plus direct
  typed event emit/wait helpers on workflow event refs.
- Added module-first bootstrap improvements including module merge/combine,
  inferred worker subscriptions, queue/subscription inspection helpers, and
  shared app/client workflow bootstrap helpers.
- Expanded manual serialization support with `json(...)`, `versionedJson(...)`,
  `versionedMap(...)`, registry-backed versioned factories, and codec-backed
  low-level publish/start/emit helpers for tasks, workflows, and queue events.
- Added broad typed decode helpers across runtime, inspection, signal, queue,
  status, and context surfaces so DTO reads no longer require raw map casts in
  the common path.
- Refreshed examples and docs to use the narrowed happy-path APIs and to treat
  transport objects as explicit advanced APIs rather than peer entrypoints.

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
