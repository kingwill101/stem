# Mobile background execution

## Status and scope

Core `StemApp.runUntilIdle` provides **admission-bounded execution with safe
draining**. An application-owned Android Workmanager example demonstrates its
callback boundary. Neither the runner nor `createApp` grants OS background time.

Available today:

- `StemFlutter.createApp` and `StemFlutterSqlite.createApp` return normal
  `StemApp` instances.
- Core Stem owns task definitions, queue consumption, execution modes, retries,
  leases, results, and explicit `start` / `shutdown`.
- SQLite queues and results survive reopening, subject to retention.
- `runUntilIdle` runs a fresh app until observed idle, its admission deadline,
  a supplied cancellation signal, or an infrastructure failure, then shuts down
  the app and its owned resources.

Not supplied by the integration packages:

- WorkManager registration, Android foreground-service hosting, or iOS
  background-task hosting. The example owns its Workmanager registration.
- Automatic propagation of native expiration/cancellation to a Stem invocation.
- A hard wall-clock deadline or forced interruption of active inline handlers.

The default demo remains a foreground app. Its alternate Android entrypoint
uses Workmanager with a producer-only UI. The photo demo performs real image
processing in task isolates, but remains a bounded sample workload—not a
guarantee of arbitrary platform execution time or workload eligibility.

## Ownership: bring your scheduler

The application owns **when the OS permits execution**. Stem owns **how Stem
tasks execute during that opportunity**.

| Application / platform integration | Stem |
| --- | --- |
| Workmanager initialization and callback dispatcher | Normal task definitions and modules |
| Android manifest and iOS capability/identifier configuration | Queue routing, claims, and lease renewal |
| Network, charging, battery, and timing constraints | Task-level retries and result persistence |
| Foreground-service eligibility, type, notification, and user actions | Core worker execution and cancellation semantics |
| Requesting, cancelling, and reconciling scheduler wakeups | Admission-bounded execution and structured outcomes |
| Mapping an invocation outcome to platform retry/rescheduling | Store ownership and orderly cleanup |

`stem_flutter` will not depend on or initialize Workmanager implicitly. Apps
already using that plugin keep their existing dispatcher and registrations.

The app still needs the standard top-level entrypoint required by Workmanager,
including its `@pragma('vm:entry-point')` annotation. That is the plugin's
entrypoint, **not an app-written Stem worker protocol**. There should be no
Stem-specific send ports, command maps, or manual consume/ack loop.

The rationale is recorded in
[ADR 0004](../../stem/doc/adr/0004-mobile-background-execution.md).

## Select the right execution mechanism

| Requirement | Mechanism to evaluate | Important limits |
| --- | --- | --- |
| Android: deferred, persistent processing | Android WorkManager through an app-selected integration | Execution is scheduled, not immediate; constraints, quotas, and stop requests apply |
| Android: user starts substantial work and minimizes the app | An appropriately declared foreground service; supported long-running WorkManager integration where suitable | Requires legitimate service type/permissions and user-visible notification; background-start and service-specific limits apply |
| iOS 26+: continue user-initiated processing after minimizing | `BGContinuedProcessingTask` through a suitable platform integration | Submit from the foreground in response to a user action; admission, resources, progress, and cancellation are OS-controlled |
| iOS: deferred processing, including older supported versions | `BGProcessingTask` through an app-selected integration | The OS chooses execution time; handle expiration and do not promise immediate continuation |

On Android 16, long-running WorkManager jobs can exhaust job quotas even when
WorkManager uses a foreground service. A direct foreground service may be more
appropriate for eligible user-initiated work. There is no universal
"unlimited CPU job" service type: classify the real workload rather than
mislabeling it as data sync.

iOS continued processing is a platform capability, not a claim that every
version of the Flutter Workmanager plugin exposes it. Verify the selected
integration and deployment targets.

Minimizing, locking the screen, process termination, task cancellation, and
force-stop are different scenarios. Neither a Dart isolate nor SQLite bypasses
platform execution limits. Do not promise continuation after user force-stop.

## Core callback entrypoint

Create a fresh app in each scheduler callback and call `runUntilIdle` instead
of `start`. This is the same core API on Flutter and other Dart VM hosts:

```dart
final app = await StemFlutterSqlite.createApp(module: myModule);
final outcome = await app.runUntilIdle(
  budget: const Duration(seconds: 30),
  shutdownReserve: const Duration(seconds: 5),
  idleTimeout: const Duration(seconds: 1),
  // Optional: a Future<void> completed by your host's stop/expiration hook.
  cancellation: stopRequested,
);
// The one-shot app and its factory-owned resources are now shut down.
// Inspect outcome.reason, outcome.deliveriesProcessed, and outcome.error.
```

`myModule` and `stopRequested` are app-owned inputs. Omit `cancellation` when
the selected platform integration does not expose a usable stop hook. The
example Workmanager integration does not pretend to provide such a hook.

The invocation requires a fresh app; do not call `start()` first or reuse a
closed app. Low-level hosts can call `Worker.runUntilIdle` instead, in which
case the caller still owns the broker/backend handles.

Bounded invocations accept task-queue subscriptions, not broadcast
subscriptions. A fire-and-forget broadcast cannot provide the durable requeue
semantics required when admission stops.

`budget` must be greater than `shutdownReserve`, which must be non-negative;
`idleTimeout` must be positive. Admission stops at `budget - shutdownReserve`.
App/database creation happens before the run, so include that startup cost
when selecting a budget for a platform callback.

`idleTimeout` is an observed quiet period with no active delivery lifecycle,
not a distributed proof that a queue is empty. Choose an interval longer than
the transport's polling/read latency. Deferred tasks and later arrivals still
need another wakeup. No queue-count polling is used to decide completion.

| `WorkerRunStopReason` | Meaning |
| --- | --- |
| `idle` | The worker observed the configured quiet period |
| `budgetExceeded` | The admission deadline stopped new claims; active work drained |
| `cancelled` | The supplied cancellation signal or shutdown stopped admission |
| `failed` | Worker startup/transport/runtime handling failed; inspect `error` and `stackTrace` |

`deliveriesProcessed` counts complete delivery lifecycles, **not successful
tasks**. Task results remain in the backend. A handled task failure or task retry
does not by itself make the invocation `failed`.

Argument validation errors and app resource-disposal errors can still throw.
The app attempts all configured factory disposers; do not interpret a cleanup
failure as a successful scheduler invocation.

This invocation mode is intentionally not a long-lived daemon: it does not
install process-signal handlers, run the control-plane consumer or autoscaler,
or publish periodic worker heartbeats. Task execution, task heartbeats, leases,
and normal task-result semantics remain active. It uses conservative prefetch
of one per selected queue rather than the daemon's configured prefetch; a
single-queue invocation therefore processes tasks serially.

### Admission limits are not hard execution limits

Cancellation and the admission deadline stop new work; they do not inject task
revocations, kill arbitrary inline code, or automatically checkpoint handlers.
The runner waits for active handling, acknowledgement, post-run work, and
resource cleanup. A still-running inline Future can therefore delay return
beyond the requested budget, including after a task-level timeout.

Use short/checkpointed work units and appropriate task execution limits.
The native host can still terminate the process before cleanup finishes; normal
durable lease/retry recovery applies. Never describe the reserve as guaranteed
OS grace time.

### Interrupted tasks and recovery policy

A process killed by Android cannot reliably emit a final Dart callback. Stem
detects **possible interrupted execution on redelivery**, when the durable result
still says `running` for that same attempt. This also happens after lease loss;
it is not proof of a process kill, and does not identify an Android exit reason.
No signal can be reconstructed if the process died before writing running state.

Core `StemSignals.taskInterrupted` reports this observation before recovery.
Subscribe in each worker runtime (signals are isolate-local), using
`package:stem/advanced.dart` for the signal API. Listeners should be short and
must not await shutdown of the worker whose callback they are handling.

Select recovery behavior on the registered task's `TaskOptions`:

```dart
const options = TaskOptions(
  maxRetries: 3,
  recoveryPolicy: TaskRecoveryPolicy.retry,
);
```

- `TaskRecoveryPolicy.replay` is the compatibility default: execute the recovered
  attempt again without spending a task retry.
- `TaskRecoveryPolicy.retry` treats that observation as `TaskInterruptedException`
  through the existing task retry classification, backoff, and retry limit.
  Retry filters can reject it; with no retries remaining the task fails normally.

These are **task retries**, distinct from a WorkManager invocation retry.
Task recovery still requires a durable broker, a surviving result record, expired
lease reclamation, and another execution opportunity. Do not shorten leases below
real execution/renewal latency just to make recovery look immediate. Recovery can
repeat side effects: use idempotency keys, durable checkpoints, and verified
output commit markers rather than assuming an interrupted attempt did nothing.

The example's Workmanager 0.9.3 integration does not expose native `onStopped`
as a Dart cancellation callback; Android's worker tears down its Flutter engine.
Do not invent a cancellation signal that the host cannot deliver. A different
host that exposes a cooperative stop hook can pass it to `cancellation`.
Android `ApplicationExitInfo` can provide diagnostics after restart, but is not
a per-task failure oracle and is not automatically queried by `stem_flutter`.

### Reducing memory pressure

Keep CPU work isolated and concurrency conservative. Large images may allocate
several buffers simultaneously; split large workloads into independently
recoverable items. For workloads retaining large task-isolate heaps, existing
worker lifecycle options can retire isolates between items:

```dart
const workerConfig = StemWorkerConfig(
  concurrency: 1,
  prefetchMultiplier: 1,
  lifecycle: WorkerLifecycleConfig(
    installSignalHandlers: false,
    maxTasksPerIsolate: 1,
  ),
);
```

This trades isolate startup overhead for shorter-lived task heaps. It does not
cap peak memory within an item, reclaim the entire Flutter engine, or prevent
Android from killing the process. The memory-recycling threshold is sampled
after execution using process RSS, not a hard per-isolate allocation limit.

Local status notifications are observability only. They do not make a callback
a foreground service or protect it from low-memory termination. After a kill,
an old notification may remain until the next opportunity to reconcile it.

### Application-owned Workmanager callback

The runnable Android example is
[`lib/workmanager_main.dart`](../../stem/example/flutter_stem_example/lib/workmanager_main.dart).
Only that app entrypoint initializes Workmanager. The normal Linux/foreground
demo and the Flutter libraries do not.

The callback follows this lifecycle:

```text
Application registers its platform callback and scheduling policy
    |
Application persists Stem work, then requests a scheduler wakeup
    |
OS invokes the registered callback when eligible
    |
Callback initializes its Flutter/platform dependencies
    |
Callback opens its own runtime using the same module and store configuration
    |
Stem runs eligible work within the supplied execution window
    |
Stem stops admission, drains active execution safely, and cleans up
    |
Callback maps the invocation outcome to platform completion/rescheduling
```

The callback must await execution and cleanup. Returning success immediately
after `app.start()` only says startup finished; it does not say work finished.
Wrapping a long-lived app in `Future.timeout` is also not a bounded runner:
timing out a Future does not stop its underlying task or make it safe to close
resources the task still uses.

Leave time for acknowledgement and cleanup before the expected platform limit.
An admission budget is not a hard termination guarantee for arbitrary inline
code. Use core isolate execution for CPU-heavy handlers where appropriate;
inline/native work must honor the cancellation facilities it actually supports.

Do not build a second implementation around `TaskProcessor.process`: that API
does not own broker consumption, acknowledgements, or leases. `runUntilIdle`
reuses core worker lifecycle behavior rather than recreating it in Flutter.

## Callback-local state and SQLite

Scheduler callbacks may run in another isolate, Flutter engine, or process.

- Reconstruct handlers from the same module definition. Registering that module
  in each runtime is normal isolate-local initialization, not maintaining a
  second set of task definitions.
- Use the same durable database paths, namespace, and selected queue. Otherwise
  the callback may successfully process an unrelated empty queue.
- Reopen database connections in the callback. Do not pass a live `StemApp`,
  Ormed `DataSource`, database connection, closure, or widget through scheduler
  input data.
- Initialize plugins/services in the callback as required by its host. Do not
  assume the foreground app's dependency initialization has run there.
- `StemFlutterSqlite.createApp` performs required Ormed/Carbonized asset setup.
  Manual SQLite adapters should call `StemFlutterSqlite.initialize()` before
  opening their Ormed-backed stores.
- Preserve factory ownership. Dispose callback-created adapters; leave a
  caller-owned data source to its owner. Never close foreground handles from a
  background callback.

An application must decide which runtime consumes each queue. If foreground
and background workers can overlap, rely on broker leases rather than an
isolate-local "already running" flag, and budget their aggregate CPU/memory
concurrency. Sharing a SQLite file is not a guarantee that arbitrary application
transactions and queue enqueueing are atomic.

Checkpoint long operations through appropriate durable workflow/task design,
or split them into idempotent chunks. Recovery does not automatically resume an
ordinary Dart function from its last instruction. Durable workflows also need
a workflow store; a task result backend is not a workflow store.

## Wakeups, retries, and result mapping

**A scheduler invocation and a Stem task are not the same unit of work.**

Normally, persist a logical Stem task once, then ask the OS for an opportunity
to process the queue. Do not enqueue another copy each time Workmanager retries
its callback. When a callback intentionally discovers new business work, use
stable idempotency keys.

Stem retains task retry/backoff policy. Workmanager retry policy applies to
the host invocation. A task recorded as failed or scheduled for a Stem retry
does not automatically mean the scheduler invocation itself failed.

The Flutter Workmanager documentation describes these platform differences:

| Callback result | Android | iOS |
| --- | --- | --- |
| `true` | Invocation succeeds | Invocation succeeds |
| `false` | WorkManager requests a retry with backoff | App must arrange rescheduling; do not assume Android retry behavior |
| Thrown error | Invocation fails, rather than automatically retrying | Invocation fails; no automatic retry is implied |

Verify behavior for the plugin version used by the app. The adapter must map
structured runner outcomes deliberately; it must not turn every task failure
or user cancellation into an endless scheduler retry.

Delayed Stem retries need a future execution opportunity. Do not keep a mobile
callback alive waiting for their ETA. The scheduler integration needs a wakeup
or reconciliation policy for deferred and newly enqueued work.

Persisting a task and registering OS work are not one transaction. Handle:

1. A task committed just before scheduler registration fails or the app dies.
2. A new task arriving while the existing callback is deciding it is idle.
3. A unique-work policy that discards a new wakeup because an older invocation
   is still registered.

Use durable wakeup intent and/or reconciliation appropriate to the application.
Unique scheduling alone is not an exactly-once or no-lost-wakeup guarantee.

## Validation and remaining integration work

Core and SQLite tests cover bounded admission, idle/delayed work, cancellation,
delivery lifecycle completion, safe resource ownership, and reopening durable
work for another invocation. These tests do not replace native lifecycle tests.

Each production scheduler integration still needs to validate:

- Native cancellation/expiration propagation, if supported by that host.
- Callback retries, overlapping foreground/background consumers, abrupt process
  termination, and the persist-before-wakeup race.
- WorkManager constraints/quotas or the chosen foreground-service/iOS policy.
- Workloads that can finish or checkpoint before the actual OS execution limit.

Scheduler registration and native policy remain in the application example or
an explicit opt-in integration, not hidden in `createApp`.

Device acceptance must include a representative heavy workload in
profile/release mode: minimize, lock/unlock, return to the UI, exercise charging
and network constraints, cancel work, and test process termination separately
from force-stop. Verify durable results, safe recovery, responsive UI,
notifications/progress where required, and bounded resource use.

Until those gates pass, foreground success and persistence tests must not be
reported as validated background-work support.

## Platform references

- [Flutter Workmanager quick start](https://docs.page/fluttercommunity/flutter_workmanager/quickstart)
- [Flutter Workmanager task results and platform retry differences](https://docs.page/fluttercommunity/flutter_workmanager/task-status)
- [Android long-running workers and Android 16 job quotas](https://developer.android.com/develop/background-work/background-tasks/persistent/how-to/long-running)
- [Android foreground-service changes and restrictions](https://developer.android.com/develop/background-work/services/fgs/changes)
- [Apple continued processing for user-initiated work](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- [Apple BGProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)
