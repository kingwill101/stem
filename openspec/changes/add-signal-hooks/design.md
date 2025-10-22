## Overview
Stem needs a first-class signal system analogous to Celery’s dispatch layer. Goals:

- Provide named signals for task lifecycle, worker lifecycle, scheduler events, and control-plane actions.
- Allow handlers to subscribe with filtering (e.g., task name) and receive structured payloads.
- Ensure low overhead when unused; signals can be disabled or lazily instantiated.

## Signal Inventory & Mapping
Celery exposes more than 30 lifecycle signals. We only need a curated subset that maps cleanly to Stem concepts; remaining signals are either deprecated (`task_sent`) or tied to Celery internals (eventlet pool hooks).

| Celery Signal | Category | Semantics | Proposed Stem Signal |
| --- | --- | --- | --- |
| `before_task_publish`, `after_task_publish` | Coordinator | Fire around broker publish | `StemSignals.beforeTaskPublish`, `StemSignals.afterTaskPublish` (dispatched from `Stem.enqueue`) |
| `task_prerun`, `task_postrun` | Worker task lifecycle | Pre/post handler execution | `StemSignals.taskPrerun`, `StemSignals.taskPostrun` |
| `task_retry`, `task_success`, `task_failure`, `task_internal_error` | Worker task result | Retry scheduling, success, failure, unhandled exceptions | `StemSignals.taskRetry`, `StemSignals.taskSucceeded`, `StemSignals.taskFailed`, `StemSignals.taskErrored` |
| `task_received`, `task_revoked`, `task_rejected`, `task_unknown` | Worker queue | Message accepted, revoked, rejected, unknown task | `StemSignals.taskReceived`, `StemSignals.taskRevoked`, `StemSignals.taskRejected`, `StemSignals.taskUnknown` |
| `before_task_publish` (legacy `task_sent`) | Coordinator | Envelope about to be published | merged above |
| `worker_init`, `worker_ready`, `worker_shutdown`, `worker_shutting_down` | Worker lifecycle | Process setup/teardown notifications | `StemSignals.workerInit`, `StemSignals.workerReady`, `StemSignals.workerStopping`, `StemSignals.workerShutdown` |
| `worker_before_create_process`, `worker_process_init`, `worker_process_shutdown` | Pool worker processes | Spawn/teardown of child isolates | `StemSignals.workerChildInit`, `StemSignals.workerChildShutdown` (maps to Stem isolate pool events) |
| `heartbeat_sent` | Heartbeat | Worker heartbeat flush | `StemSignals.workerHeartbeat` (emitted via heartbeat transport) |
| `beat_init`, `beat_embedded_init` | Scheduler | Scheduler startup | `StemSignals.schedulerInit` |
| (Celery has `beat_scheduler_ready`, `beat_schedule` via docs) | Scheduler | Entry due/sent | `StemSignals.scheduleEntryDue`, `StemSignals.scheduleEntryDispatched`, `StemSignals.scheduleEntryFailed` |
| `import_modules`, `celeryd_after_setup`, `celeryd_init` | Worker bootstrap | Module import + config | folded into `workerInit` (no dedicated Stem signal required) |
| Logging/user preload signals | CLI | logger setup / CLI preload options | not planned for initial parity; out-of-scope for MVP |

The above mapping ensures we cover every Celery signal that real-world projects rely upon for instrumentation or operational hooks. Non-applicable signals (e.g., `eventlet_pool_*`) are intentionally omitted; we can revisit if users request them.

## Signal Registry & API
We expose a strongly typed registry so consumers can discover signals via autocomplete and documentation:

```dart
typedef SignalHandler<T> = FutureOr<void> Function(T payload, SignalContext ctx);

class StemSignals {
  static final beforeTaskPublish =
      Signal<BeforeTaskPublishPayload>(name: 'before-task-publish');
  static final taskPrerun =
      Signal<TaskPrerunPayload>(name: 'task-prerun', defaultFilter: TaskFilter.any);
  // ... one static member per signal described above.
}
```

Key API decisions:

- **Registration** – `Signal<T>.connect(handler, {SignalFilter? filter, bool once = false, int priority = 0})` returns a `SignalSubscription` that can be cancelled. We accept sync/async handlers; dispatch awaits in priority order.
- **Filtering** – We provide built-in filter factories (`TaskFilter.byName('foo')`, `WorkerFilter.byId('worker-1')`, `ScheduleFilter.byEntry('nightly')`). Filters are simple predicates evaluated before invoking handlers.
- **Context** – `SignalContext` carries metadata such as `sender`, timestamps, and a `cancelled` flag so handlers can request stop-propagation (used sparingly, default false).
- **Dispatch** – `Signal<T>.emit(payload, {String? sender})` or internal `dispatch` method checks the `SignalConfig` for enablement, short-circuits when no handlers are connected, and logs (but swallows) handler exceptions.
- **Namespaces** – The registry lives in `package:stem/stem_signals.dart`. Users import the singleton or individual signals. Advanced users can instantiate their own `SignalHub` for testing.

### Configuration & Feature Flags

- `StemSignalConfig.enabled` (global toggle) and per-signal toggles (e.g., `enabledSignals: {'task-prerun': true}`). Defaults keep all signals enabled; we skip dispatch when disabled.
- `SignalDispatcherConcurrency` option controls whether async handlers are awaited sequentially (default) or concurrently. Sequential execution preserves ordering semantics critical for audit logs.
- `StemSignals.configure({SignalLogger? logger})` allows overriding error reporting and instrumentation hooks.

### Error Handling

- Handler exceptions are caught, logged through the configured logger, and surfaced via a dedicated `StemSignals.signalDispatchFailed` signal so observers can react.
- We record handler latency with `StemMetrics` once per signal, enabling future alerting on slow handlers.

## Payload Structures
Define small immutable payload classes capturing relevant context (similar to Celery keyword args). Examples:
```dart
class TaskPrerunPayload {
  final String taskName;
  final Envelope envelope;
  final TaskContext context;
}

class WorkerReadyPayload {
  final String workerId;
  final DateTime timestamp;
  final List<String> queues;
}
```
Ensure serialization not required but provide `toMap()` for logging.

## Integration Points
- **Coordinator**: Emit `beforeTaskPublish` and `afterTaskPublish` around `Broker.publish`; `task_enqueued` when entering retry pipeline; `app_ready` when Stem instance initialized.
- **Worker**: Emit `workerStarting`, `workerReady`, `workerShutdown`, `taskReceived`, `taskPrerun`, `taskPostrun`, `taskSuccess`, `taskFailure`, `taskRetry`, `taskRevoked`, `taskUnknown`.
- **Scheduler**: Emit `scheduleEntryDue`, `scheduleEntryExecuted`, `scheduleEntryFailed`, `scheduleSync`.
- **Control Plane**: Emit `controlCommandReceived`, `controlCommandCompleted` for remote control interactions.

## Middleware Bridge
- Adapt existing middleware to optionally forward events to signals, enabling incremental adoption. Provide helper `SignalMiddleware` to translate signal registration into middleware callbacks. Also allow middleware to emit signals manually.

## Performance Considerations
- Signals default-enabled but dispatch cost is ~O(number of subscribed handlers); short-circuit when no handlers or when disabled in config.
- Dispatcher uses a lightweight subscriber list; we avoid `StreamController` due to allocation overhead and to preserve synchronous ordering guarantees.
- We expose a benchmark harness to gauge per-signal overhead with N handlers (goal: <3µs per handler for synchronous callbacks).

## Error Handling
- Signal handlers must never crash worker/coordinator. We guard each handler invocation, emit `signalDispatchFailed`, and log a structured warning.
- Handlers receive only `(payload, ctx)`; we avoid kwargs to keep API uniform. Additional metadata (e.g., exception info) resides in the payload type.

## Testing Strategy
- Unit tests for signal dispatcher (connect/disconnect, filtering, async handlers).
- Integration tests verifying signals fire in appropriate order during task lifecycle (enqueue → execute → finish).
- Tests demonstrating disabling signals removes overhead.
