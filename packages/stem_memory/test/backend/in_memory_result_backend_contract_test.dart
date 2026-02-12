import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_memory/stem_memory.dart';

void main() {
  runResultBackendContractTests(
    adapterName: 'in-memory',
    factory: ResultBackendContractFactory(
      create: () async => InMemoryResultBackend(
        heartbeatTtl: const Duration(seconds: 1),
      ),
      dispose: (backend) => backend.close(),
    ),
  );
}
