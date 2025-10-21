## Overview
Stem needs a first-class signal system analogous to Celery’s dispatch layer. Goals:

- Provide named signals for task lifecycle, worker lifecycle, scheduler events, and control-plane actions.
- Allow handlers to subscribe with filtering (e.g., task name) and receive structured payloads.
- Ensure low overhead when unused; signals can be disabled or lazily instantiated.

## Signal Registry & API
Create `StemSignals` singleton exposing typed registration methods:
```dart
class StemSignals {
  static final beforeTaskPublish = Signal<BeforeTaskPublishPayload>();
  static final afterTaskPublish = Signal<AfterTaskPublishPayload>();
  static final taskReceived = Signal<TaskReceivedPayload>();
  // ... others
}

StemSignals.taskPrerun.connect(handler, {String? taskName});
StemSignals.workerReady.connect(handler, {String? workerId});
```

`Signal<T>` supports:
- `connect(handler, {String? sender})`
- `disconnect(handler)`
- `dispatch(payload, {String sender})`
- Optionally `once`, `priority` for ordering.

Handlers may be sync or async (Future). Dispatcher awaits futures sequentially or concurrently based on configuration.

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

## Performance & Configuration
- Signals default-enabled. Provide global toggle or per-signal toggle for high-throughput environments; when disabled, dispatch becomes a no-op.
- Dispatch overhead minimized by short-circuiting when no handlers connected.
- Consider using `StreamController.broadcast` internally for async dispatch with error handling (log and continue).

## Error Handling
- Signal handlers should not crash the worker/coordinator. Catch and log exceptions; optionally expose `signalError` hook for observability.
- Document expectation that handlers accept `payload` plus optional kwargs (future-proofing).

## Testing Strategy
- Unit tests for signal dispatcher (connect/disconnect, filtering, async handlers).
- Integration tests verifying signals fire in appropriate order during task lifecycle (enqueue → execute → finish).
- Tests demonstrating disabling signals removes overhead.
