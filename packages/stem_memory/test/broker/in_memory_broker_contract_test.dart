import 'package:stem_adapter_tests/stem_adapter_tests.dart';
import 'package:stem_memory/stem_memory.dart';

void main() {
  runBrokerContractTests(
    adapterName: 'in-memory',
    factory: BrokerContractFactory(
      create: () async => InMemoryBroker(
        claimInterval: const Duration(milliseconds: 100),
        defaultVisibilityTimeout: const Duration(seconds: 1),
      ),
      dispose: (broker) async => broker.close(),
      additionalBrokerFactory: () async => InMemoryBroker(
        claimInterval: const Duration(milliseconds: 100),
        defaultVisibilityTimeout: const Duration(seconds: 1),
      ),
    ),
    settings: const BrokerContractSettings(
      capabilities: BrokerContractCapabilities(
        verifyBroadcastFanout: true,
      ),
    ),
  );
}
