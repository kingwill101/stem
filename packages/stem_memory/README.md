# stem_memory

In-memory broker, backend, workflow, and scheduler adapters for Stem.

## Install

```bash
dart pub add stem_memory
```

## Usage

```dart
import 'package:stem/stem.dart';
import 'package:stem_memory/stem_memory.dart';

Future<void> main() async {
  final stem = Stem(
    broker: InMemoryBroker(),
    registry: SimpleTaskRegistry(),
    backend: InMemoryResultBackend(),
  );

  await stem.close();
}
```

## Factories

Use `memoryBrokerFactory`, `memoryBackendFactory`, `memoryWorkflowStoreFactory`,
`memoryEventBusFactory`, `memoryScheduleStoreFactory`, `memoryLockStoreFactory`,
and `memoryRevokeStoreFactory` to integrate with bootstrap helpers.
