# Worker Package Documentation

> **Comprehensive documentation for the Stem Worker subsystem**
>
> This document serves as a complete reference for new team members to understand the worker package architecture, classes, methods, and their interactions.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [File Structure](#file-structure)
4. [Core Classes](#core-classes)
   - [Worker](#worker)
   - [TaskIsolatePool](#taskisolatepool)
   - [Configuration Classes](#configuration-classes)
   - [Isolate Messages](#isolate-messages)
5. [Enums](#enums)
6. [Quick Start Guide](#quick-start-guide)
7. [Advanced Topics](#advanced-topics)

---

## Overview

The **Worker Package** is the task execution runtime of the Stem task queue framework. It:

- Consumes tasks from a message broker
- Executes registered task handlers with full lifecycle management
- Supports concurrent execution via isolates for isolation and performance
- Provides observability features: metrics, tracing, heartbeats, and logging
- Implements retry policies, rate limiting, and graceful shutdown semantics

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Worker                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Broker    │  │  Registry   │  │    Result Backend       │  │
│  │ (consume)   │  │ (handlers)  │  │  (persist state)        │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
│         │                │                     │                 │
│         ▼                ▼                     ▼                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Task Handler Loop                      │   │
│  │  - Rate limiting    - Retry policies    - Middleware     │   │
│  │  - Heartbeats       - Lease renewal     - Revocation     │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  TaskIsolatePool                          │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐         │   │
│  │  │Isolate 1│ │Isolate 2│ │Isolate 3│ │Isolate N│         │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Structure

| File | Lines | Description |
|------|-------|-------------|
| `worker.dart` | 3374 | Main worker runtime - task consumption, lifecycle, observability |
| `isolate_pool.dart` | 573 | Isolate pool management for concurrent task execution |
| `isolate_messages.dart` | 177 | Message types for isolate communication |
| `worker_config.dart` | 136 | Configuration classes for autoscaling and lifecycle |

---

## Core Classes

### Worker

**File:** `worker.dart` (Lines 58-3244)

The main runtime that consumes tasks from a broker and executes handlers.

#### Constructor Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `broker` | `Broker` | **required** | Message broker for publishing/consuming |
| `registry` | `TaskRegistry` | **required** | Registry containing task handlers |
| `backend` | `ResultBackend` | **required** | Backend for persisting task state |
| `enqueuer` | `Stem?` | `null` | Stem instance for spawning child tasks |
| `rateLimiter` | `RateLimiter?` | `null` | Rate limiter for task execution |
| `middleware` | `List<Middleware>` | `[]` | Middleware chain for lifecycle hooks |
| `revokeStore` | `RevokeStore?` | `null` | Store for task cancellation |
| `uniqueTaskCoordinator` | `UniqueTaskCoordinator?` | `null` | Coordinator for task uniqueness |
| `retryStrategy` | `RetryStrategy?` | `ExponentialJitterRetryStrategy()` | Strategy for computing retry delays |
| `queue` | `String` | `'default'` | Default queue name |
| `subscription` | `RoutingSubscription?` | `null` | Custom routing subscription |
| `consumerName` | `String?` | `null` | Consumer identifier |
| `concurrency` | `int?` | `Platform.numberOfProcessors` | Maximum concurrent tasks |
| `prefetchMultiplier` | `int` | `2` | Prefetch count multiplier |
| `prefetch` | `int?` | `null` | Override prefetch count |
| `heartbeatInterval` | `Duration` | `10 seconds` | Task heartbeat interval |
| `workerHeartbeatInterval` | `Duration?` | `null` | Worker-level heartbeat interval |
| `heartbeatTransport` | `HeartbeatTransport?` | `NoopHeartbeatTransport()` | Transport for heartbeats |
| `heartbeatNamespace` | `String` | `'stem'` | Namespace for observability |
| `autoscale` | `WorkerAutoscaleConfig?` | `null` | Autoscaling configuration |
| `lifecycle` | `WorkerLifecycleConfig?` | `null` | Lifecycle configuration |
| `observability` | `ObservabilityConfig?` | `null` | Metrics and tracing config |
| `signer` | `PayloadSigner?` | `null` | Payload signature verifier |
| `encoderRegistry` | `TaskPayloadEncoderRegistry?` | `null` | Custom encoder registry |
| `resultEncoder` | `TaskPayloadEncoder` | `JsonTaskPayloadEncoder()` | Encoder for results |
| `argsEncoder` | `TaskPayloadEncoder` | `JsonTaskPayloadEncoder()` | Encoder for arguments |
| `additionalEncoders` | `Iterable<TaskPayloadEncoder>` | `[]` | Additional payload encoders |

#### Public Fields

| Field | Type | Description |
|-------|------|-------------|
| `broker` | `Broker` | Broker for consuming/acknowledging deliveries |
| `registry` | `TaskRegistry` | Task handler registry |
| `backend` | `ResultBackend` | Result persistence backend |
| `rateLimiter` | `RateLimiter?` | Optional rate limiter |
| `middleware` | `List<Middleware>` | Middleware chain |
| `retryStrategy` | `RetryStrategy` | Retry delay computation |
| `queue` | `String` | Default queue name |
| `consumerName` | `String?` | Consumer identifier |
| `uniqueTaskCoordinator` | `UniqueTaskCoordinator?` | Uniqueness coordinator |
| `concurrency` | `int` | Max concurrent tasks |
| `prefetchMultiplier` | `int` | Prefetch multiplier |
| `prefetch` | `int` | Broker prefetch count |
| `autoscaleConfig` | `WorkerAutoscaleConfig` | Autoscaling settings |
| `lifecycleConfig` | `WorkerLifecycleConfig` | Lifecycle settings |
| `heartbeatInterval` | `Duration` | Task heartbeat interval |
| `workerHeartbeatInterval` | `Duration` | Worker heartbeat interval |
| `heartbeatTransport` | `HeartbeatTransport` | Heartbeat publisher |
| `namespace` | `String` | Observability namespace |
| `signer` | `PayloadSigner?` | Payload signature verifier |
| `revokeStore` | `RevokeStore?` | Task cancellation store |
| `payloadEncoders` | `TaskPayloadEncoderRegistry` | Encoder registry |
| `subscription` | `RoutingSubscription` | Routing subscription |
| `subscriptionQueues` | `List<String>` | Resolved queue names |
| `subscriptionBroadcasts` | `List<String>` | Broadcast channel names |
| `events` | `Stream<WorkerEvent>` | Event stream for task lifecycle |
| `activeConcurrency` | `int` | Current active concurrency |
| `primaryQueue` | `String` | Primary queue name |

#### Public Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `start()` | `Future<void> start()` | Starts the worker, subscribes to queues, begins task consumption |
| `shutdown()` | `Future<void> shutdown({WorkerShutdownMode mode = WorkerShutdownMode.hard})` | Stops the worker with configurable shutdown semantics |

#### Private Methods (Internal Implementation)

| Method | Description |
|--------|-------------|
| `_handle(Delivery)` | Handles a single broker delivery end-to-end |
| `_runConsumeMiddleware(Delivery)` | Executes consume middleware before task handling |
| `_notifyErrorMiddleware(TaskContext, Object, StackTrace)` | Notifies middleware about task processing errors |
| `_invokeWithMiddleware(TaskContext, Future<dynamic> Function())` | Invokes handler through middleware chain |
| `_executeWithHardLimit(TaskHandler, TaskContext, Envelope, Map)` | Runs handler with optional hard time limit |
| `_scheduleSoftLimit(Envelope, TaskOptions)` | Schedules soft timeout warning |
| `_startHeartbeat(String)` | Starts heartbeat timer for a task |
| `_scheduleLeaseRenewal(Delivery)` | Schedules visibility/lease renewal |
| `_restartLeaseTimer(Delivery, Duration)` | Restarts lease timer after renewal |
| `_startLeaseTimer(Delivery, Duration)` | Starts lease renewal timer |
| `_cancelLeaseTimer(String)` | Cancels lease renewal tracking |
| `_noteLeaseRenewal(Delivery)` | Records lease renewal timestamp |
| `_releaseUniqueLock(Envelope)` | Releases unique task locks |
| `_maybeDispatchChord(GroupStatus)` | Dispatches chord callbacks when group completes |
| `_dispatchLinkedTasks(Envelope, {bool onSuccess})` | Enqueues linked tasks for chains/chords |
| `_decodeTaskOptions(Object?)` | Decodes task options from metadata |
| `_decodeTaskEnqueueOptions(Object?)` | Decodes enqueue options from metadata |
| `_parseDateTime(Object?)` | Parses DateTime from various formats |
| `_isTerminalState(TaskState)` | Checks if task state is terminal |
| `_handleSignatureFailure(...)` | Dead-letters envelopes with invalid signatures |
| `_handleFailure(...)` | Handles task failure with retries and status updates |
| `_handleRetryRequest(...)` | Handles explicit retry requests from handlers |
| `_rateLimitKey(TaskOptions, Envelope)` | Builds rate-limit key |
| `_parseRate(String)` | Parses rate limit string (e.g., "10/m") |
| `_sendHeartbeat(String)` | Emits heartbeat update for running task |
| `_trackDelivery(Delivery)` | Tracks in-flight delivery |
| `_releaseDelivery(Envelope)` | Removes delivery from tracking |
| `_recordInflightGauge()` | Records in-flight task count metric |
| `_recordConcurrencyGauge()` | Records active concurrency metric |
| `_recordQueueDepth()` | Updates queue depth metrics |
| `_collectQueueDepths()` | Collects pending counts per queue |
| `_cancelAllSubscriptions()` | Cancels broker subscriptions |
| `_cancelTimers()` | Cancels active runtime timers |
| `_disposePool()` | Disposes isolate pool |
| `_forceStopActiveTasks()` | Forcibly stops tasks, requeues deliveries |
| `_requestTerminationForActiveTasks({String reason})` | Requests cooperative termination |
| `_awaitDrainWithTimeout(Duration?)` | Waits for tasks to drain with timeout |
| `_stopSignalWatchers()` | Stops process signal subscriptions |
| `_recordLeaseRenewal(Delivery)` | Records lease renewal timestamp |
| `_logContext(Map)` | Adds worker metadata to log context |
| `_startWorkerHeartbeatLoop()` | Starts periodic worker heartbeat |
| `_startAutoscaler()` | Starts autoscaling evaluation timer |
| `_evaluateAutoscale()` | Evaluates autoscale rules |
| `_updateConcurrency(int, {String reason, int backlog, int inflight})` | Updates isolate pool size |
| `_cooldownElapsed(DateTime?, Duration, DateTime)` | Checks autoscale cooldown |
| `_handleIsolateRecycle(IsolateRecycleEvent)` | Handles isolate pool recycling |
| `_installSignalHandlers()` | Installs process signal handlers |
| `_safeWatch(ProcessSignal, void Function())` | Guards signal watch for unsupported platforms |
| `_parseShutdownMode(String?)` | Parses shutdown mode from value |
| `_handleShutdownRequest(WorkerShutdownMode)` | Handles control-plane shutdown requests |
| `_publishWorkerHeartbeat()` | Publishes worker heartbeat to backend |
| `_buildHeartbeat()` | Builds worker heartbeat payload |
| `_readLoadAverage()` | Reads system load average |
| `_calculatePercent(int, int)` | Calculates percentage |
| `_formatUptime(Duration)` | Formats uptime duration |
| `_reportProgress(Envelope, double, {Map? data})` | Emits progress update |
| `_initializeRevocations()` | Seeds revocation cache from store |
| `_syncRevocations()` | Syncs revocation entries from store |
| `_pruneExpiredLocalRevocations(DateTime)` | Drops expired revocations |
| `_revocationFor(String)` | Gets revocation entry for task |
| `_enforceTerminationIfRequested(String)` | Throws if task should terminate |
| `_applyRevocationEntry(RevokeEntry, {DateTime? clock})` | Applies revocation to cache |
| `_isTaskRevoked(String)` | Checks if task is revoked |
| `_resolveArgsEncoder(TaskHandler?)` | Resolves args encoder |
| `_resolveResultEncoder(TaskHandler?)` | Resolves result encoder |
| `_decodeArgs(Envelope, TaskPayloadEncoder)` | Decodes task arguments |
| `_castArgsMap(Object?, TaskPayloadEncoder)` | Normalizes args map |
| `_castObjectMap(Object?)` | Coerces to string-keyed map |
| `_castStringMap(Object?)` | Coerces to string-keyed string map |
| `_durationFromMeta(Object?)` | Parses Duration from metadata |
| `_resolveHardTimeLimit(Envelope, TaskOptions)` | Resolves hard time limit |
| `_resolveSoftTimeLimit(Envelope, TaskOptions)` | Resolves soft time limit |
| `_shouldIgnoreResult(Envelope)` | Checks if result should be persisted |
| `_resolveRetryPolicy(Envelope, TaskOptions)` | Resolves retry policy overrides |
| `_shouldAutoRetry(TaskRetryPolicy?, Object)` | Checks if failure should auto-retry |
| `_computeRetryDelay(int, Object, StackTrace, TaskRetryPolicy?)` | Computes retry delay |
| `_statusMeta(Envelope, TaskPayloadEncoder, {Map extra})` | Builds status metadata |
| `_withResultEncoderMeta(Map, TaskPayloadEncoder)` | Adds encoder metadata |
| `_handleRevokedDelivery(...)` | Marks and acks revoked deliveries |
| `_isExpired(Envelope)` | Checks if delivery is expired |
| `_handleExpiredDelivery(...)` | Marks and acks expired deliveries |
| `_processRevokeCommand(ControlCommandMessage)` | Processes revoke commands |
| `_applyRevocationEntries(List<RevokeEntry>)` | Applies revocation entries |
| `_startControlPlane()` | Starts control-plane subscription |
| `_processControlCommandDelivery(Delivery)` | Processes control command delivery |
| `_handleControlCommand(ControlCommandMessage)` | Dispatches control command handlers |
| `_sendControlReply(ControlReplyMessage)` | Sends control reply message |
| `_subscriptionMetadata()` | Returns subscription metadata |
| `_buildStatsSnapshot()` | Builds worker stats snapshot |
| `_buildInspectSnapshot({bool includeRevoked})` | Builds inspection snapshot |
| `_shouldUseIsolate(TaskHandler)` | Checks if handler should use isolate |
| `_runInIsolate(...)` | Runs task in isolate pool |
| `_controlHandler(TaskContext)` | Creates control handler for context |
| `_ensureIsolatePool()` | Ensures isolate pool is created |
| `_createPool()` | Creates new isolate pool |

#### Static Methods

| Method | Description |
|--------|-------------|
| `_normalizeConcurrency(int?)` | Normalizes concurrency value |
| `_calculatePrefetch(int?, int, int)` | Calculates prefetch count |
| `_resolveAutoscaleConfig(WorkerAutoscaleConfig?, int)` | Resolves autoscale config |

---

### TaskIsolatePool

**File:** `isolate_pool.dart` (Lines 53-378)

A pool of isolates for executing tasks concurrently with dynamic scaling and recycle policies.

#### Constructor Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `size` | `int` | **required** | Initial pool size (minimum 1) |
| `onRecycle` | `void Function(IsolateRecycleEvent)?` | `null` | Callback when isolate is recycled |
| `onSpawned` | `FutureOr<void> Function(int)?` | `null` | Callback when isolate is spawned |
| `onDisposed` | `FutureOr<void> Function(int)?` | `null` | Callback when isolate is disposed |

#### Public Properties

| Property | Type | Description |
|----------|------|-------------|
| `size` | `int` | Desired number of isolates |
| `activeCount` | `int` | Number of currently active isolates |
| `totalCount` | `int` | Total isolates (idle + active) |

#### Public Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `start()` | `Future<void> start()` | Spawns initial isolates |
| `dispose()` | `Future<void> dispose()` | Disposes pool and all isolates |
| `resize(int)` | `Future<void> resize(int newSize)` | Resizes pool, spawning or draining isolates |
| `updateRecyclePolicy({int?, int?})` | `void updateRecyclePolicy({int? maxTasksPerIsolate, int? maxMemoryBytes})` | Updates recycle thresholds |
| `execute(...)` | `Future<TaskExecutionResult> execute(...)` | Executes a task in an available isolate |

#### Private Methods

| Method | Description |
|--------|-------------|
| `_pump()` | Processes job queue, assigns jobs to idle isolates |
| `_shouldRecycle(_PoolEntry)` | Determines if isolate should be recycled |
| `_determineRecycleReason(_PoolEntry)` | Determines recycle reason |
| `_disposeEntry(_PoolEntry, {IsolateRecycleReason})` | Disposes entry with reason |
| `_ensureCapacity()` | Spawns isolates to meet target size |
| `_notifySpawned(_IsolateWorker)` | Invokes spawned callback |
| `_notifyDisposed(_IsolateWorker)` | Invokes disposed callback |
| `_disposeWorker(_PoolEntry)` | Disposes worker isolate |

---

### Configuration Classes

**File:** `worker_config.dart`

#### WorkerAutoscaleConfig

Autoscaling configuration for worker concurrency (Lines 1-89).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | `bool` | `false` | Whether autoscaling is active |
| `minConcurrency` | `int` | `1` | Minimum isolates when autoscaling |
| `maxConcurrency` | `int?` | `null` | Maximum concurrency (null = use worker concurrency) |
| `scaleUpStep` | `int` | `1` | Isolates to add when scaling up |
| `scaleDownStep` | `int` | `1` | Isolates to remove when scaling down |
| `backlogPerIsolate` | `double` | `1.0` | Queue backlog per isolate before scaling up |
| `idlePeriod` | `Duration` | `30 seconds` | Idle time before scaling down |
| `tick` | `Duration` | `2 seconds` | Autoscaler evaluation interval |
| `scaleUpCooldown` | `Duration` | `5 seconds` | Cooldown between scale-up actions |
| `scaleDownCooldown` | `Duration` | `10 seconds` | Cooldown between scale-down actions |

**Methods:**
- `copyWith(...)` - Returns a copy with provided overrides

**Named Constructors:**
- `WorkerAutoscaleConfig.disabled()` - Disabled autoscaling profile

#### WorkerLifecycleConfig

Lifecycle guard configuration for worker isolates and shutdown (Lines 92-135).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `installSignalHandlers` | `bool` | `true` | Install SIGTERM/SIGINT/SIGQUIT handlers |
| `softGracePeriod` | `Duration` | `30 seconds` | Grace period before hard termination |
| `forceShutdownAfter` | `Duration` | `10 seconds` | Time before forcing cancellation |
| `maxTasksPerIsolate` | `int?` | `null` | Tasks before recycling (null = disabled) |
| `maxMemoryPerIsolateBytes` | `int?` | `null` | Memory threshold before recycling |

**Methods:**
- `copyWith(...)` - Returns a copy with provided overrides

---

### Isolate Messages

**File:** `isolate_messages.dart`

Classes for communication between the main isolate and worker isolates.

#### TaskRunRequest (Lines 11-47)

Request to run a task in an isolate.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Task ID for the invocation |
| `entrypoint` | `TaskEntrypoint` | Function to execute |
| `args` | `Map<String, Object?>` | Arguments to pass |
| `headers` | `Map<String, String>` | Headers for invocation |
| `meta` | `Map<String, Object?>` | Metadata for invocation |
| `attempt` | `int` | Attempt number |
| `controlPort` | `SendPort` | Control signal port |
| `replyPort` | `SendPort` | Reply port for response |

#### TaskRunResponse (Lines 50-53)

Sealed base class for task run responses.

#### TaskRunSuccess (Lines 56-65)

Successful task run response.

| Field | Type | Description |
|-------|------|-------------|
| `result` | `Object?` | Execution result |
| `memoryBytes` | `int?` | RSS after execution |

#### TaskRunFailure (Lines 68-80)

Failed task run response.

| Field | Type | Description |
|-------|------|-------------|
| `errorType` | `String` | Error type name |
| `message` | `String` | Error message |
| `stackTrace` | `String` | Stack trace string |

#### TaskRunRetry (Lines 83-111)

Retry request from isolate task.

| Field | Type | Description |
|-------|------|-------------|
| `countdownMs` | `int?` | Relative delay in milliseconds |
| `eta` | `String?` | Absolute retry timestamp (ISO-8601) |
| `retryPolicy` | `Map<String, Object?>?` | Serialized retry policy |
| `maxRetries` | `int?` | Max retries override |
| `timeLimitMs` | `int?` | Hard time limit override |
| `softTimeLimitMs` | `int?` | Soft time limit override |

#### TaskWorkerShutdown (Lines 114-117)

Shutdown signal for worker isolates.

#### taskWorkerIsolate (Lines 119-176)

Entry point function that runs the worker isolate event loop.

---

## Enums

### WorkerShutdownMode

**File:** `worker.dart` (Lines 46-55)

| Value | Description |
|-------|-------------|
| `warm` | Allows in-flight tasks to complete without draining new work |
| `soft` | Drains worker, requests cooperative termination, escalates to hard if ignored |
| `hard` | Immediately stops and cancels active work, requeues in-flight deliveries |

### IsolateRecycleReason

**File:** `isolate_pool.dart` (Lines 15-27)

| Value | Description |
|-------|-------------|
| `scaleDown` | Recycled due to pool scaling down |
| `maxTasks` | Recycled after reaching max task limit |
| `memory` | Recycled after exceeding memory limit |
| `shutdown` | Recycled during shutdown |

### WorkerEventType

**File:** `worker.dart` (Lines 3287-3314)

| Value | Description |
|-------|-------------|
| `heartbeat` | Heartbeat signal for active task |
| `progress` | Progress update for task |
| `timeout` | Soft timeout warning |
| `completed` | Task completed successfully |
| `retried` | Task scheduled for retry |
| `failed` | Task failed permanently |
| `revoked` | Task was revoked |
| `error` | Error occurred outside task execution |

---

## Additional Classes

### WorkerEvent

**File:** `worker.dart` (Lines 3249-3286)

Event emitted during worker operation with task lifecycle details.

### TaskRevokedException

**File:** `worker.dart` (Lines 3316-3331)

Exception thrown when a task is revoked during execution.

### IsolateRecycleEvent

**File:** `isolate_pool.dart` (Lines 30-46)

Metadata describing an isolate recycle event.

| Field | Type | Description |
|-------|------|-------------|
| `reason` | `IsolateRecycleReason` | Why the isolate was recycled |
| `tasksExecuted` | `int` | Tasks executed before recycling |
| `memoryBytes` | `int?` | Last RSS reading if available |

### TaskExecutionResult (sealed)

**File:** `isolate_pool.dart` (Lines 409-412)

Base class for task execution results.

### TaskExecutionSuccess

**File:** `isolate_pool.dart` (Lines 415-424)

Successful execution with result value.

### TaskExecutionFailure

**File:** `isolate_pool.dart` (Lines 427-436)

Failed execution with error and stack trace.

### TaskExecutionRetry

**File:** `isolate_pool.dart` (Lines 439-445)

Retry request from isolate task.

### TaskExecutionTimeout

**File:** `isolate_pool.dart` (Lines 448-457)

Timed-out execution for a task.

---

## Private/Internal Classes

### _TaskJob

**File:** `isolate_pool.dart` (Lines 381-406)

Internal job representation for isolate execution queue.

### _PoolEntry

**File:** `isolate_pool.dart` (Lines 459-466)

Internal pool entry tracking isolate worker state.

### _IsolateWorker

**File:** `isolate_pool.dart` (Lines 468-533)

Internal isolate worker wrapper with spawn/run/dispose lifecycle.

### _RemoteTaskError

**File:** `isolate_pool.dart` (Lines 558-572)

Error wrapper for remote task execution failures.

### _RateSpec

**File:** `worker.dart` (Lines 3334-3345)

Parsed rate limit specification (tokens + period).

### _ActiveDelivery

**File:** `worker.dart` (Lines 3348-3373)

Tracks an active task delivery for lifecycle management.

---

## Quick Start Guide

### Basic Worker Setup

```dart
import 'package:stem/stem.dart';

// 1. Create your broker, registry, and backend
final broker = InMemoryBroker();
final registry = TaskRegistry();
final backend = InMemoryResultBackend();

// 2. Register task handlers
registry.register('my_task', TaskHandler(
  (context, args) async {
    // Your task logic here
    return {'result': 'success'};
  },
));

// 3. Create and start the worker
final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  concurrency: 4, // Process 4 tasks concurrently
);

await worker.start();

// 4. Graceful shutdown
await worker.shutdown(mode: WorkerShutdownMode.soft);
```

### With Autoscaling

```dart
final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  concurrency: 16, // Maximum concurrency
  autoscale: WorkerAutoscaleConfig(
    enabled: true,
    minConcurrency: 2,
    maxConcurrency: 16,
    backlogPerIsolate: 2.0,
    scaleUpCooldown: Duration(seconds: 5),
    scaleDownCooldown: Duration(seconds: 30),
  ),
);
```

### With Lifecycle Configuration

```dart
final worker = Worker(
  broker: broker,
  registry: registry,
  backend: backend,
  lifecycle: WorkerLifecycleConfig(
    installSignalHandlers: true,
    softGracePeriod: Duration(seconds: 60),
    maxTasksPerIsolate: 1000,
    maxMemoryPerIsolateBytes: 256 * 1024 * 1024, // 256MB
  ),
);
```

### Listening to Events

```dart
worker.events.listen((event) {
  switch (event.type) {
    case WorkerEventType.completed:
      print('Task ${event.envelope?.id} completed');
      break;
    case WorkerEventType.failed:
      print('Task failed: ${event.error}');
      break;
    case WorkerEventType.retried:
      print('Task retried');
      break;
    default:
      break;
  }
});
```

---

## Advanced Topics

### Shutdown Modes

1. **Warm Shutdown** - Lets in-flight tasks complete without accepting new work
2. **Soft Shutdown** - Requests cooperative termination, waits for grace period, then escalates
3. **Hard Shutdown** - Immediately stops all tasks, requeues deliveries

### Isolate Pool Lifecycle

1. Pool is created lazily when first isolate-based task is executed
2. Isolates are recycled based on:
   - Max tasks per isolate threshold
   - Memory usage threshold
   - Scale-down operations
3. Pool adjusts size based on autoscale configuration

### Task Lifecycle Hooks

The worker provides several lifecycle hooks via middleware:
- Consume middleware (before task handling)
- Invoke middleware (around task execution)
- Error middleware (on failures)

### Rate Limiting

Rate limits are specified as strings like:
- `"10/s"` - 10 requests per second
- `"100/m"` - 100 requests per minute
- `"1000/h"` - 1000 requests per hour

---

## See Also

- [Stem Core Documentation](../core/README.md)
- [Broker Implementations](../brokers/README.md)
- [Result Backends](../backends/README.md)
