import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';

void main() {
  runRevokeStoreContractTests(
    adapterName: 'in-memory',
    factory: RevokeStoreContractFactory(
      create: () async => InMemoryRevokeStore(),
      dispose: (store) => store.close(),
    ),
  );
}
