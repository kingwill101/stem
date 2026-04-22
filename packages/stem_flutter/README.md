# stem_flutter

Flutter integration primitives for hosting Stem workers inside a Flutter app.

`stem_flutter` is the adapter-neutral layer. It does not choose a broker or
result backend for you. Instead, it gives Flutter apps the pieces they usually
need around a Stem worker:

- spawning and supervising a worker isolate
- translating isolate messages into typed worker signals
- polling queue depth, heartbeats, and recent jobs into a UI-friendly snapshot
- keeping that coordination code out of widget trees and app bootstrap code

If you want the SQLite-specific runtime and worker bootstrap helpers, use
`stem_flutter_sqlite` on top of this package.

## What This Package Includes

- `StemFlutterWorkerHost`: supervises a worker isolate and exposes a stream of
  `StemFlutterWorkerSignal` values
- `StemFlutterQueueMonitor`: polls a `Broker` and `ResultBackend`, then merges
  that data with worker signals
- `StemFlutterQueueSnapshot`: compact queue and worker state intended for UI
  rendering

## What This Package Does Not Do

- guarantee always-on background execution on iOS or Android
- hide mobile lifecycle limits or process restarts
- pick a specific broker or result backend
- provide an OS scheduler or background-task wrapper

Those decisions are intentionally left to the app and the adapter package.

## Installation

```yaml
dependencies:
  stem_flutter: ^0.1.0
```

## Minimal Usage

`stem_flutter` is generic, so the broker and backend in this example can come
from Redis, SQLite, Postgres, or another Stem adapter.

```dart
import 'dart:isolate';

import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';

Future<void> workerMain(Map<String, Object?> message) async {
  final sendPort = message['sendPort']! as SendPort;
  final commands = ReceivePort();

  sendPort.send(
    StemFlutterWorkerSignal.ready(
      commandPort: commands.sendPort,
      detail: 'Worker isolate ready.',
    ).toMessage(),
  );

  // Start your Stem Worker here...

  await for (final dynamic command in commands) {
    if (command is Map && command['type'] == 'shutdown') {
      break;
    }
  }

  commands.close();
}

Future<void> startMobileWorker({
  required Broker broker,
  required ResultBackend backend,
}) async {
  final host = await StemFlutterWorkerHost.spawn<Map<String, Object?>>(
    entrypoint: workerMain,
    messageBuilder: (sendPort) => <String, Object?>{'sendPort': sendPort},
  );

  final monitor = StemFlutterQueueMonitor(
    backend: backend,
    broker: broker,
    queueName: 'mobile-demo',
    workerId: 'mobile-worker',
  )..bindWorkerSignals(host.signals);

  await monitor.start();
}
```

## Mobile Recommendations

- Keep the UI isolate producer-oriented. Do not run the worker on the main
  isolate if you can avoid it.
- Use a separate isolate for the worker and report status back through
  `StemFlutterWorkerSignal`.
- Treat `StemFlutterQueueMonitor` as an observation layer. It reports queue and
  heartbeat state; it does not drive execution.
- Prefer polling `listTaskStatuses()` or heartbeats for cross-isolate status
  views. Backend-specific `watch(taskId)` streams are often process-local.

## Example

The recommended mobile structure lives in
`packages/stem/example/flutter_stem_example`.

That example shows how to combine `stem_flutter` with
`stem_flutter_sqlite` to:

- open a producer runtime on the UI isolate
- launch a separate worker isolate
- monitor pending, inflight, and recent-job state from Flutter

## Related Package

Use `stem_flutter_sqlite` when you want:

- application-support-directory storage layout
- SQLite-backed broker and result backend helpers
- worker bootstrap payloads for Flutter background isolates
- a convenience launcher for SQLite worker isolates
