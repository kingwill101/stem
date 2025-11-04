import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:test/test.dart';

void main() {
  test('exports contract runners', () {
    expect(runBrokerContractTests, isNotNull);
    expect(runResultBackendContractTests, isNotNull);
    expect(runLockStoreContractTests, isNotNull);
    expect(runWorkflowStoreContractTests, isNotNull);
  });
}
