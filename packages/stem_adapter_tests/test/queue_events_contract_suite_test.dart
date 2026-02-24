import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/stem_adapter_tests.dart';

void main() {
  final namespace = 'adapter-tests-${DateTime.now().microsecondsSinceEpoch}';

  runQueueEventsContractTests(
    adapterName: 'in-memory',
    factory: QueueEventsContractFactory(
      create: () async => InMemoryBroker(namespace: namespace),
      dispose: (broker) => broker.close(),
      additionalBrokerFactory: () async => InMemoryBroker(namespace: namespace),
      additionalDispose: (broker) => broker.close(),
    ),
  );
}
