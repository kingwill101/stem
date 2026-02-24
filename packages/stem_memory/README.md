# stem_memory

In-memory broker, backend, workflow, and scheduler adapters for Stem.

## Install

```bash
dart pub add stem_memory
```

## Usage

```dart
import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_memory/stem_memory.dart';

Future<void> main() async {
  final client = await StemClient.inMemory(
    tasks: [
      FunctionTaskHandler(
        name: 'demo.memory',
        entrypoint: (context, args) async => 'ok',
      ),
    ],
  );
  final worker = await client.createWorker();
  unawaited(worker.start());

  final taskId = await client.stem.enqueue('demo.memory');
  print((await client.stem.waitForTask<String>(taskId))?.value);

  await worker.shutdown();
  await client.close();
}
```

## Factories

Use `memoryBrokerFactory`, `memoryResultBackendFactory`,
`memoryWorkflowStoreFactory`, `memoryEventBusFactory`,
`memoryScheduleStoreFactory`, `memoryLockStoreFactory`, and
`memoryRevokeStoreFactory` to integrate with bootstrap helpers.
