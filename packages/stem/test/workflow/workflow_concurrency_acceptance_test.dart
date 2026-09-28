import 'package:stem/memory.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';

void main() {
  runWorkflowConcurrencyContractTests(
    adapterName: 'in-memory',
    factory: WorkflowStoreContractFactory(
      create: (clock) async => InMemoryWorkflowStore(clock: clock),
    ),
  );
}
