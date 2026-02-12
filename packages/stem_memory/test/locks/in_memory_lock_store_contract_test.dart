import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_memory/stem_memory.dart';

void main() {
  runLockStoreContractTests(
    adapterName: 'in-memory',
    factory: LockStoreContractFactory(
      create: () async => InMemoryLockStore(),
    ),
  );
}
