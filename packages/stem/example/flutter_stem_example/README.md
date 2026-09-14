# Stem Workbench

An offline task and durable-workflow workbench using the ordinary core `StemApp`,
initialized for Flutter by `stem_flutter_sqlite`. The Tasks tab retains Photo
Lab: each photo is a real CPU task that generates a
sample landscape, encode/decode JPEG, enhance and resize it, then write a preview,
thumbnail, and checksum manifest.

The Tasks view shows bounded batches, durable per-photo results, elapsed processing time,
output sizes, and thumbnails you can inspect. Processing uses core task isolates,
not the UI isolate. Photo processing has no artificial sleeps or personal-photo permissions,
custom worker messages, or manually coordinated worker database handles.

## Demo gallery

Run `flutter run -t lib/demos_main.dart` for a landing page with one button
per demo. Each demo owns its `WorkflowHost` and submits workflows with typed
input, awaiting `run.result` on the current screen.

- **Greeter** (`lib/greeting_main.dart` also runs it standalone,
  `lib/src/greeting_workflow.dart`, `lib/src/greeting_page.dart`): type a
  name, tap **Greet me**, and the screen shows the workflow's result. The
  `greet` checkpoint runs inside `Isolate.run`, so the returned string names
  both the UI isolate and the worker isolate that computed it.
  `test/greeting_page_test.dart` drives the same flow with a widget test.
- **Mini Medusa: cart checkout** (`lib/src/cart/`): a Medusa-style commerce
  flow. `cart.checkout` chains `validate-cart`, `reserve-inventory`,
  `charge-payment`, and fulfillment checkpoints with registered compensation
  handlers (`release-reservation` restocks, `refund-payment` voids the
  charge). The pack/ship step implementations are shared with
  `cart.fulfill-order`, so fulfillment runs inline in checkout or standalone
  from the **Run fulfillment workflow alone** button — the Stem analogue of
  Medusa's nested workflows. Toggle **Decline card** or **Empty stock** to
  watch rollback, then read the step and compensation logs.
  `test/cart_page_test.dart` covers the happy path and the declined-card
  rollback.

## Tasks and workflows

The bottom navigation switches between Tasks, Workflows, and Workers. Switching
tabs does not stop publication or close app-owned stores.

- **Tasks:** submit a single photo or Quick/Standard/Heavy batches even when
  earlier requests are queued. Each request is bounded to at most 12 photos;
  publication is single-flight, but outstanding work does not block another
  explicit request. Results retain their own batch IDs.
- **Workflows:** select a checkpointed report, a durable sleep/resume flow, or a
  run-specific approval flow. Launch 1–5 independent runs per request, inspect
  persisted checkpoints and results, approve only the selected waiting run, or
  cancel a run. Progress reflects core workflow state, not a simulated timer.

Workflow history shows 20 runs per selected workflow/status page, with explicit
Previous/Next controls. Other pages or workflow types may contain active runs.
Checkpoint details load when **Saved checkpoints** is expanded or reloaded;
unchanged summaries retain cached details rather than rereading every checkpoint
each second. Changed runs offer an explicit reload of their details.

Workflows use `StemWorkflowApp` layered onto the same task app, with a separate
`workflows.sqlite` file under the same application-support root. Definitions are
registered again in every foreground runtime and every headless callback. The
UI is producer/observer-only in Workmanager mode; it does not start a hidden
worker or workflow poller to make background work appear successful.

The sleep scenario defaults to a ten-second durable suspension. This is a
workflow scheduling example, not artificial CPU load. A bounded callback can
return idle while a run sleeps. It schedules a separate timed **wakeup**, which
only appends to the existing serial drain chain when Android permits it to run.
The periodic reconciler remains a fallback. Waiting for approval requires an
explicit event, not repeated scheduled execution. Native scheduling failure is
reported separately from persisted workflow launch; do not launch duplicate
runs to retry a wakeup.

Background startup scans overdue runs and stops/joins polling before the worker
starts. Sleeps created during that callback remain suspended for the host's next
wakeup; a late poll cannot enqueue behind a worker that has stopped admitting.
Foreground mode keeps periodic polling. Shutdown stops/joins polling, drains
the worker, then closes the borrowed
workflow layer and owned task stores. `StemApp.runUntilIdle` alone would close
its stores too early for an external workflow layer; the example uses the core
worker's one-shot runner and explicit owner cleanup.

### Worker topology

The default entrypoints demonstrate **both shared and dedicated queues**:

| Worker identity | Subscriptions | Task-isolate slots |
| --- | --- | --- |
| `general-a` | `mobile-demo` (photos, workflows, routing probes) | 1 |
| `general-b` | `mobile-demo` (the same queue) | 1 |
| `routing-worker` | `mobile-routing` | 1 |

These are ordinary `StemApp` workers configured with `StemWorkerConfig`,
`consumerName`, and explicit `RoutingSubscription`s. They open the same durable
SQLite files; Stem handles claiming, leases, ACKs, retries and execution.
Each general worker reconstructs its own workflow runtime and definitions.
There is no custom dispatcher, consume loop, IPC protocol or replacement lock
manager for worker execution.

Use the **Workers** tab to submit lightweight routing probes to either queue.
Persisted results show the queue and the worker that actually handled each task,
using normal task-status metadata. Competing consumers are not round-robin:
one worker may receive more tasks than another. Queue isolation and correct
settlement matter, not perfectly equal distribution.

Foreground mode starts all three workers with normal `start()` calls. One
Android WorkManager callback hosts the three Stem workers concurrently using
their normal bounded runners; this does not create three native Android jobs or
promise three parallel Flutter engines. The callback joins all runner futures
and observer reads before closing their owned resources.

Each bounded worker observes its own subscriptions becoming idle. After a
productive multi-worker callback, the host requests one fresh serial
reconciliation callback to catch cross-queue work published after another worker
became idle. An empty reconciliation does not request another, so it is not an
idle spin loop. Normal task retries remain Stem's responsibility.

Worker count and per-worker isolate concurrency are different. Here up to two
workers can process photo tasks concurrently, increasing aggregate memory use;
start with routing probes or single photos before Heavy batches. Background
UI labels show configuration and persisted observations, not a fabricated
headless-worker liveness status.

Stem supports competing workers on shared queues. Stale-owner workflow writes
after lease expiry remain a specific recovery/fencing test concern, not a
restriction on demonstrating normal multi-worker operation.

See [multi-worker validation](doc/multiworker-validation.md) for the real SQLite
tests, current native-install status, and the routing-probe acceptance procedure.

Workflow checkpoints do not make external side effects exactly-once. There is
also no atomic transaction spanning due-run extraction and broker enqueue in
the generic runtime; process termination or a transport failure between those
operations remains a recovery limitation. The new normal shutdown and
reopen/resume tests do not prove that every abrupt-termination window is safe.

See [workflow validation](doc/workflow-validation.md) for the SQLite/widget test
coverage, observed Android report/sleep/approval outcomes, and remaining limits.

## Workloads and outputs

| Preset | Photos | Source resolution |
| --- | --- | --- |
| Quick | 3 | 960 × 640 |
| Standard (default) | 6 | 1600 × 1000 |
| Heavy | 12 | 2048 × 1536 |

Each photo is a separate durable task, so a background invocation can stop
admitting work between photos and a later invocation can continue the batch.
Heavier presets increase real image work rather than sleeping to simulate load.
Exact duration depends on the device and build mode; start with Quick.

Generated artifacts live under the demo's application-support storage in a
batch-specific photo directory. Results include source/preview/thumbnail paths,
byte counts, elapsed milliseconds, and a SHA-256 checksum. Outputs survive
reopening the demo. Retrying the same task checks completed artifacts and can
reuse them instead of generating another copy. Incomplete artifacts must not be
treated as a completed photo.

New results use immutable `generation-*` artifact directories. A complete
manifest is atomically published only after all files are written, so concurrent
attempts cannot mix files or invalidate paths already returned to another caller.
Verified legacy manifests remain reusable. Obsolete completed generations are
retained because persisted task results may reference them; abrupt termination
can also leave an unpublished generation. Reclaiming these needs an explicit
album/result retention policy rather than deleting files during a retry.

The demo only touches its own generated sample files. It does not access your
camera roll, upload photos, or delete personal files. Batches consume disk space;
avoid repeatedly generating Heavy batches when only testing scheduling.

## Runtime

`lib/src/app.dart` owns the app above the monitor screen:

```dart
final app = await StemFlutterSqlite.createApp(module: demoModule);
await app.start();

final monitor = QueueDebugController(
  app,
  queueName: queueName,
);
await monitor.start();

// When the application owner is finished:
await monitor.dispose();
await app.close(); // Alias for the core app.shutdown().
```

The factory returns a real core `StemApp`; it does not start consumption.
The module supplies the task registrations and the worker's queue subscription
is inferred from those tasks. SQLite's normal defaults apply. The default
layout puts separate broker and result files in the application support
directory. Supply `layout` or `storage: StemFlutterSqliteConfig(...)` when
different paths or retention/lease settings are needed.

For other stores, `StemFlutter.createApp` provides the same core application
with Flutter initialization and local-worker defaults, using core broker/backend
factories. Task definitions, modules, results, Canvas, `start`, and `shutdown`
remain normal Stem APIs.

## Typed tasks

`lib/src/demo_tasks.dart` defines `PhotoTaskArgs`, a
`TaskDefinition<PhotoTaskArgs, Map<String, Object?>>`, and the shared module.
Both the foreground worker and Workmanager callback use that same definition.
A batch publishes one typed call per photo:

```dart
final taskId = await app.enqueueCall(
  preparePhoto.buildCall(
    PhotoTaskArgs(
      outputDirectory: outputDirectory.path,
      batchId: batchId,
      index: 0,
      width: 1600,
      height: 1000,
    ),
    meta: {
      'batchId': batchId,
      'batchSize': 6,
      'label': 'Photo 1',
    },
  ),
);
```

`buildCall` is the core typed-call builder. Serialization is defined once in the
task definition. Only scalar arguments and paths cross the core task-isolate
boundary; no Flutter widgets, database handles, or plugins are sent to it.

## Execution and lifecycle

The worker coordinator is hosted with the application; photo handlers execute
through core Stem's isolate pool. This keeps image generation/filtering/JPEG
encoding off the UI isolate. SQLite coordination remains in its owning runtime.
The handler uses pure Dart image/file APIs, not Flutter plugins. This does not
mean arbitrary plugins can be used in a task isolate.

The example-only `QueueDebugController` uses existing core data APIs:
`backend.listTaskStatuses(TaskStatusListRequest(queue: queueName))`,
`broker.pendingCount`, and `broker.inflightCount`. Widgets present the returned
`TaskStatusRecord` / `TaskStatus` directly. No library monitor or additional
diagnostic models are needed.

Reads refresh on local worker events, batch publication, resume, and explicit
refresh. While the view is visible and work remains, lightweight reconciliation
also observes progress made by a separate Workmanager engine. Reconciliation
stops when idle, hidden, or disposed. It also catches acknowledgements that
complete after a task's success event.

Batch progress is based on persisted photo states, not a fake timer. Coarse
task-isolate progress events are local observations; per-photo completion and
outputs are the durable source of truth after reopening. The local worker's
started flag is not a claim about the health of a separate Workmanager engine.

The screen owns only its change subscription; removing that screen must not
shut down application work. Root disposal waits for any pending app creation or
start, then awaits controller disposal and any active read before closing the
app and its stores.
Flutter's synchronous widget `dispose` launches that orderly asynchronous
cleanup, but cannot force the OS to wait for it.

## Persistence and recovery

SQLite persistence is **not guaranteed background execution**. Suspending,
killing, or hot-restarting Flutter can stop execution without graceful shutdown.
The default `lib/main.dart` does not register a background scheduler.
The alternate Android entrypoint below demonstrates app-owned Workmanager
registration and Stem-owned bounded execution.
See the [background execution guide](../../../stem_flutter/doc/background-execution.md)
before extending the demo with Workmanager or a foreground service.

Once the app is running again, interrupted deliveries become eligible for
recovery after their visibility lease expires and broker maintenance runs.
Dashboard refresh only observes storage; it neither wakes a suspended worker nor
claims jobs. Queue counts and task status can briefly differ while a newly
published task awaits its first status update.

Handlers must be idempotent: retries or recovery can repeat a delivery after a
side effect succeeded but before acknowledgment was persisted. Use stable
business/idempotency keys and transactional updates where appropriate. Result
retention and dead-letter retention also mean persisted records are not kept
forever.

## Run and verify

```bash
cd packages/stem/example/flutter_stem_example
flutter pub get
flutter devices
flutter run -d linux # Or use the device ID of an Android/iOS device.
flutter test
flutter analyze
```

iOS, Linux, and macOS Dart VM targets use the same structure; this SQLite demo
is not a web-storage example.

The unit/widget tests use tiny image workloads with temporary output directories.
The device integration test uses the same `createDemoApp` factory as the
interactive demo, real SQLite files, and actual photo outputs. It checks batch
submission, successful results, orderly shutdown, and outputs/results surviving
a new app opening the same files. Test storage is separate from normal demo data.

```bash
flutter test integration_test/sqlite_demo_test.dart -d linux
# The same test can run on a connected Android/iOS device:
flutter test integration_test/sqlite_demo_test.dart -d <device-id>
```

For a host-driven run:

```bash
flutter drive -d linux \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/sqlite_demo_test.dart
```

On desktop, add `--dart-define=STEM_DEMO_SCREENSHOT=/absolute/path/demo.png`
to save the completed-job screen during the integration test.

If jobs remain queued, inspect the worker state and startup logs, then check
visibility-lease recovery and SQLite lock contention. Separate broker/backend
files reduce contention but do not eliminate it.

## Android Workmanager mode (opt-in)

```bash
flutter pub get --offline # Cached dependencies; no PUB_TOKEN required.
flutter run --profile -d <android-device-id> -t lib/workmanager_main.dart
```

This entrypoint is Android-only. The existing foreground/Linux entrypoint is
unchanged. The shared UI is **producer/observer only**: its app is never started
as a consumer. The stopped local-worker chip is expected, not an indication of
the native worker's health. Enqueue one job, minimize/lock, return, and refresh
to observe the result. Foreground completion in this mode must come from the
scheduler callback, not a hidden UI worker.

The example now requires iOS 14 for foreground iOS builds because Workmanager's
federated Apple dependency is linked even when the Android entrypoint is unused.
Only this example's Xcode deployment targets are raised; no library deployment
policy or iOS background capabilities are added.

After testing, use **Cancel native wakeups** to cancel this demo's periodic
registration and serial drain chain (without deleting durable jobs). An already
executing Dart callback may finish; native cancellation is not a hard task abort.
Retry wakeup, another publication, or restarting Workmanager mode enables
registrations again. Uninstall the test app for complete native scheduling/data
cleanup if no further demonstration is wanted.

The application owns the `@pragma('vm:entry-point')` dispatcher, initialization,
registrations and outcome mapping in `lib/workmanager_main.dart` and
`lib/src/android_background.dart`. The callback opens a fresh `createDemoApp`
with the same default application-support SQLite paths, configuration, queue
and typed module. No live handles or business payloads cross through scheduler
input data. Each callback drains existing work; it never enqueues another task.
The core worker's `runUntilIdle` owns worker shutdown. The app host then joins
its event-triggered notification reads and closes the callback-owned stores in
`finally`; it does not start another consumer or polling loop.

Scheduling policy:

- Persist the Stem task first, then request a native wakeup. Scheduling failure
  is displayed separately from publish failure; **Retry wakeup** does not publish
  another task. Refresh after an ambiguous publish failure before retrying.
- Every drain joins one named serial WorkManager chain using
  `ExistingWorkPolicy.update`. In `workmanager_android` 0.9.3
  `WorkManagerUtils.kt`, UPDATE maps to native `APPEND_OR_REPLACE`. Unlike KEEP,
  a wakeup arriving while an invocation finishes is not discarded.
- Startup and manual retry register a unique 15-minute periodic reconciler and
  request a drain unconditionally, including work persisted by an earlier run.
  The periodic callback only appends a drain to that same chain, never consumes.
  It provides later opportunities for deferred Stem retries and registration
  gaps. Android can delay it beyond 15 minutes. This is reconciliation, not an
  atomic enqueue/schedule transaction or an exactly-once guarantee.
- Idle and cancellation complete the Android invocation. Normal budget
  exhaustion first appends a successor to the same serial chain, then returns
  success. This avoids making healthy continuation wait behind exponential
  backoff at the head of the chain. If successor registration fails, it returns
  `false` to retain Android's backoff retry; no Stem task is republished.
  A structured SocketException failure
  retries; other runner failures and configuration/programming exceptions fail
  the invocation rather than blindly retry forever. Inspect logs and fix the
  cause before manual retry. Periodic reconciliation can attempt later drains.

The 30-second budget, 5-second shutdown reserve and 1-second idle window bound
**admission**, not arbitrary inline task execution. Active tasks and ack writes
drain safely; there is no hard wall-clock deadline. Photo batches perform real
CPU and file work, but do not prove unlimited background execution. A large
batch may span several native invocations and Android scheduling delays.
Workmanager does not expose
automatic native cancellation propagation to this Dart callback. OS stops can
prevent cleanup; ordinary lease recovery still applies. There is no foreground
service, iOS background support, or force-stop continuation guarantee.
Local SQLite jobs need no network constraint and run offline; WorkManager
quotas, battery policy and deferred execution still apply offline.

### Optional Android status notification

In Workmanager mode, **Enable status notifications** requests Android's
notification permission from an explicit foreground action. Denial, a disabled
channel, or a notification plugin failure never prevents publication, worker
execution, or continuation scheduling. The headless dispatcher never prompts.
The ordinary `lib/main.dart` entrypoint does not enable these notifications.

`flutter_local_notifications` is an **example-only** dependency. One low-priority,
silent notification ID is updated for queued work, processing, budget waiting,
completion, and errors. Counts come from persisted photo task status records
for the newest pending batch, or the latest finished batch when none are pending.
Recency uses the batch's earliest record creation time (batch ID breaks ties),
not status update order; retained historical failures do not affect a new batch.
Counts do not use timers, planned-but-uncommitted photos, or the
current invocation's delivery counter. Failed/cancelled records count as finished
and are identified separately. Worker lifecycle events trigger serialized reads;
final status is read after the worker has drained and before stores close.

The worker-scoped core `taskInterrupted` signal also updates this notification
to **Interrupted work detected** when an already-running attempt is redelivered.
It reports persisted recovery evidence, not proof of an OS kill or its cause.
Recovery can defer work through the configured retry policy; this status does
not claim the photo is already executing again. The signal subscription and
its reads are disconnected/joined at the callback boundary.

Recovery tracking uses task IDs and the latest interrupted attempt. Only a
matching terminal event at that attempt or a later retry clears it; an unrelated
worker's completion cannot hide another task's recovery state.

Only active processing is ongoing. Completion, errors and waiting replace it
with a dismissible notification; cancellation and empty queues cancel it.
**Cancel native wakeups** also cancels the notification. An already executing
callback may still finish and post its final status. As best-effort stale-display
protection, active notifications expire after two minutes without a replacement.
Android process death can skip Dart cleanup; the notification is not a durable
invocation ledger, a foreground service, evidence that a worker is still alive,
or protection from process kills. Android may delay or suppress notifications.

Android configuration includes `POST_NOTIFICATIONS`, a monochrome status icon,
and core-library desugaring (`desugar_jdk_libs:2.1.4`) required by plugin 22.3.0
even though this demo does not schedule notifications. The existing AGP 8.11.1
and Java 17 configuration meet the plugin requirements; compile SDK must be at
least 35. No exact-alarm, boot-notification receivers, full-screen intent, or
foreground-service permissions are added. Flutter also links the plugin's
federated desktop/iOS dependencies; this example does not request their
notification permissions.

Native acceptance should additionally cover notification permission granted
and denied, a batch spanning budget boundaries, terminal status clearing the
ongoing flag, cancelled wakeups, and process death leaving at most the bounded
stale display. Unit tests cover routing/continuation and durable status
accounting, but do not substitute for Android scheduler/notification UI testing.

Native acceptance remains a separate gate: run profile/release on a phone,
enqueue and minimize before completion, lock/unlock, reopen and refresh;
test ordinary process termination separately from force-stop, startup
reconciliation, delayed retries and failed scheduling/manual recovery.
Do not use `integration_test/sqlite_demo_test.dart` as proof of background
execution: it deliberately validates the foreground runtime.

For opt-in stage memory logging and the observed process-kill/retry experiment,
see [Android recovery validation](doc/android-recovery-validation.md). That
report separates measured recovery from still-unverified termination scenarios;
neither a local notification nor per-photo isolate recycling prevents OS kills.
