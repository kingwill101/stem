import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_memory/stem_memory.dart';

void main() {
  final inMemoryFactory = WorkflowStoreContractFactory(
    create: (clock) async => InMemoryWorkflowStore(clock: clock),
  );
  runWorkflowStoreContractTests(
    adapterName: 'in-memory',
    factory: inMemoryFactory,
  );
  runWorkflowScriptFacadeTests(
    adapterName: 'in-memory',
    factory: inMemoryFactory,
  );
}
