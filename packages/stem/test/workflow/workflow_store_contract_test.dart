import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';

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
