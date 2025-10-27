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
}
```

## Versioning

This package follows the same release cadence as the `stem` runtime.
