# stem_adapter_tests

Shared contract test suites used by Stem adapter packages to ensure brokers and
result backends satisfy the core runtime contract. Intended as a dev dependency
for packages like `stem_redis`, `stem_postgres`, and custom adapter
implementations.

## Install

Add as a dev dependency:

```bash
dart pub add --dev stem_adapter_tests
```

Then invoke the contract suites from your package tests:

```dart
import 'package:stem_adapter_tests/stem_adapter_tests.dart';

void main() {
  runBrokerContractTests(
    adapterName: 'MyBroker',
    factory: BrokerContractFactory(create: createBroker),
  );

  final storeFactory = WorkflowStoreContractFactory(create: createWorkflowStore);

  runWorkflowStoreContractTests(
    adapterName: 'my-adapter',
    factory: storeFactory,
  );

  // Facade coverage validates the high-level workflow DSL across adapters.
  runWorkflowScriptFacadeTests(
    adapterName: 'my-adapter',
    factory: storeFactory,
  );
}
```

The workflow store suite exercises durable watcher semantics (`registerWatcher`,
`resolveWatchers`, and `listWatchers`) so adapters must capture event payloads
atomically and expose waiting runs for operator tooling.

## Versioning

This package follows the same release cadence as the `stem` runtime.
