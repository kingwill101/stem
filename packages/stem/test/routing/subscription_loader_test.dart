import 'package:stem/src/core/config.dart';
import 'package:stem/src/routing/routing_config.dart';
import 'package:stem/src/routing/routing_registry.dart';
import 'package:stem/src/routing/subscription_loader.dart';
import 'package:test/test.dart';

void main() {
  group('buildWorkerSubscription', () {
    final routingConfig = RoutingConfig(
      defaultQueue: const DefaultQueueConfig(
        alias: 'default',
        queue: 'default',
      ),
      queues: {
        'default': QueueDefinition(name: 'default'),
        'critical': QueueDefinition(name: 'critical'),
      },
      broadcasts: {'announcements': BroadcastDefinition(name: 'announcements')},
    );
    final registry = RoutingRegistry(routingConfig);

    StemConfig configFor({
      List<String>? workerQueues,
      List<String>? workerBroadcasts,
    }) {
      return StemConfig(
        brokerUrl: 'redis://localhost:6379',
        workerQueues: workerQueues,
        workerBroadcasts: workerBroadcasts,
      );
    }

    test('defaults to the configured default queue', () {
      final subscription = buildWorkerSubscription(
        config: configFor(),
        registry: registry,
      );
      expect(subscription.queues, equals(['default']));
      expect(subscription.broadcastChannels, isEmpty);
    });

    test('resolves queue overrides via registry aliases', () {
      final subscription = buildWorkerSubscription(
        config: configFor(workerQueues: ['critical']),
        registry: registry,
      );
      expect(subscription.queues, equals(['critical']));
    });

    test('resolves broadcast overrides', () {
      final subscription = buildWorkerSubscription(
        config: configFor(workerBroadcasts: ['announcements']),
        registry: registry,
      );
      expect(subscription.broadcastChannels, equals(['announcements']));
    });

    test('throws when queue does not exist', () {
      expect(
        () => buildWorkerSubscription(
          config: configFor(workerQueues: ['missing']),
          registry: registry,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
