# Stem Signals

> **Note:** This doc is mirrored on the published site at
> `.site/docs/signals.md`; keep both versions aligned.

Stem exposes Celery-style lifecycle hooks via a strongly typed signal
dispatcher. Signals supplement middleware so instrumentation, observability,
and auditing code can react to task, worker, scheduler, and control-plane
events without patching the runtime.

## Signal Catalog

| Category | Stem Signal | Payload Highlights | Celery Equivalent |
| --- | --- | --- | --- |
| Publish | `beforeTaskPublish`, `afterTaskPublish` | `Envelope`, attempt, task id | `before_task_publish`, `after_task_publish` |
| Worker lifecycle | `workerInit`, `workerReady`, `workerStopping`, `workerShutdown`, `workerHeartbeat`, `workerChildInit`, `workerChildShutdown` | `WorkerInfo`, optional reason/timestamp | `worker_init`, `worker_ready`, `worker_shutting_down`, `worker_shutdown`, `heartbeat_sent`, `worker_process_init/shutdown` |
| Task lifecycle | `taskReceived`, `taskPrerun`, `taskPostrun`, `taskRetry`, `taskSucceeded`, `taskFailed`, `taskRevoked` | `Envelope`, `WorkerInfo`, attempt, result/error context | `task_received`, `task_prerun`, `task_postrun`, `task_retry`, `task_success`, `task_failure`, `task_revoked` |
| Scheduler | `scheduleEntryDue`, `scheduleEntryDispatched`, `scheduleEntryFailed` | `ScheduleEntry`, tick timestamp, drift, error stack | `beat_scheduler_ready`, `beat_schedule` (Celery docs) |
| Control plane | `controlCommandReceived`, `controlCommandCompleted` | `ControlCommandMessage`, reply status, payload/error map | `control_command_sent`, `control_command_received` |

Payload classes live in `package:stem/src/signals/payloads.dart` and expose
convenience getters such as `taskId`, `taskName`, and `attempt`.

## Dispatch Ordering & Semantics

- `beforeTaskPublish` fires immediately before brokers receive the envelope.
- `taskReceived` runs after middleware and before the task context is created.
- `taskPrerun` precedes handler execution; `taskPostrun` is invoked after
  completion regardless of outcome. Success and failure signals run before the
  postrun event.
- Worker lifecycle signals follow `workerInit` → `workerReady` → optional
  `workerStopping` → `workerShutdown`. Heartbeats (`workerHeartbeat`) emit on
  the configured interval and include namespace/queue metadata.
- Scheduler signals fire in the order `scheduleEntryDue` → dispatch →
  `scheduleEntryDispatched` or `scheduleEntryFailed`.
- When handlers throw, Stem logs a structured warning and continues invoking
  remaining listeners unless the handler calls `SignalContext.cancel()`.

Signals execute sequentially by default, preserving registration priority.
Handlers can be synchronous or `async`; awaiting is enforced to maintain order.

## Configuration & Performance

The dispatcher short-circuits when disabled, so the overhead is effectively the
cost of iterating registered handlers. Configuration options:

- Programmatic toggle:

  ```dart
  StemSignals.configure(
    configuration: const StemSignalConfiguration(
      enabled: true,
      enabledSignals: {'worker-heartbeat': false},
    ),
  );
  ```

- Environment variables parsed via `ObservabilityConfig.fromEnvironment`:
  - `STEM_SIGNALS_ENABLED=false` disables the dispatcher globally.
  - `STEM_SIGNALS_DISABLED=worker-heartbeat,task-prerun` disables selected
    signals while leaving others active.

Workers automatically apply the signal configuration supplied through
`ObservabilityConfig`, so fleet-wide changes can be rolled out via environment
variables or config files.

## Bridging & Adapters

- **`StemSignalEmitter`** (exported at `package:stem/stem.dart`) builds payloads
  and emits signals without duplicating boilerplate. It is used internally by
  `Stem`, `Worker`, and the scheduler, and is suitable for custom middleware or
  broker adapters that need to publish signals manually.
- **`SignalMiddleware`** bridges existing middleware chains to signals. The
  `coordinator` constructor forwards enqueue middleware to publish signals,
  while the `worker` constructor emits `taskReceived`, `taskPrerun`, and
  `taskFailed` from consume/execute hooks. Success and postrun signals still
  flow through the core runtime for accurate result payloads.

## Docker Example

`examples/signals_demo` provisions a Redis broker, producer, and worker. Running

```bash
docker compose up --build
```

prints each signal as structured JSON, illustrating retries, failures, worker
heartbeats, control commands, and scheduler events with no additional setup.

### Focused Retry Demo

Need to watch a failing task exhaust its retries quickly? `examples/retry_task`
launches a single worker plus producer that enqueues one task configured with
`maxRetries = 2`. The worker:

- sets `ExponentialJitterRetryStrategy(base: 200ms, max: 1s)` so retry delays
  stay sub-second, and
- connects to Redis with `blockTime=100ms`, `claimInterval=200ms`, and
  `defaultVisibilityTimeout=2s` so delayed entries are drained almost
  immediately.

The console output shows every `task_retry`, `task_failed`, and `task_postrun`
signal, along with the calculated `nextRunAt` timestamp. Tweak those values to
see how backoff and broker polling affect retry cadence (e.g., raise `base` to
slow down, or increase `maxRetries` in `TaskOptions` to observe more attempts).

## Celery Parity Snapshot

| Celery | Stem | Notes |
| --- | --- | --- |
| `task_prerun` / `task_postrun` | `taskPrerun` / `taskPostrun` | Payload includes `TaskContext` for heartbeat and lease helpers. |
| `worker_ready` | `workerReady` | Includes queue/broadcast subscriptions for visibility. |
| `worker_process_init/shutdown` | `workerChildInit` / `workerChildShutdown` | Emitted for isolate pool spawn/recycle events. |
| `before_task_publish` | `beforeTaskPublish` | Fires before middleware or broker IO. |
| `beat_schedule` | `scheduleEntryDispatched` | Provides scheduled vs executed timestamps to compute drift. |

Signals not relevant to Stem (e.g. eventlet pool hooks) remain intentionally
unsupported; open a proposal if parity is required.

## Testing Guarantees

Unit tests cover dispatcher priority, once-only subscriptions, filter
combinators, handler error logging, scheduler and worker lifecycle hooks, and
retry/failure dispatch. `SignalMiddleware` and the Docker example ensure
handlers observe every task outcome, mirroring Celery workloads for migration.
