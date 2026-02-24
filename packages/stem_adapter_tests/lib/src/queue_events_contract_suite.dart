import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_adapter_tests/src/contract_capabilities.dart';
import 'package:test/test.dart';

/// Settings that tune the queue events contract test suite.
class QueueEventsContractSettings {
  /// Creates queue events contract settings.
  const QueueEventsContractSettings({
    this.settleDelay = const Duration(milliseconds: 150),
    this.timeout = const Duration(seconds: 5),
    this.capabilities = const QueueEventsContractCapabilities(),
  });

  /// Delay used to let subscriptions become active before assertions.
  final Duration settleDelay;

  /// Timeout used when waiting for event deliveries.
  final Duration timeout;

  /// Feature capability flags for optional contract assertions.
  final QueueEventsContractCapabilities capabilities;
}

/// Factory hooks used by the queue events contract test suite.
class QueueEventsContractFactory {
  /// Creates a queue events contract factory.
  const QueueEventsContractFactory({
    required this.create,
    this.dispose,
    this.additionalBrokerFactory,
    this.additionalDispose,
  });

  /// Creates a broker instance used by producers/listeners.
  final Future<Broker> Function() create;

  /// Optional disposer invoked after each test.
  final FutureOr<void> Function(Broker broker)? dispose;

  /// Optional second broker factory used for fan-out verification.
  final Future<Broker> Function()? additionalBrokerFactory;

  /// Optional disposer for brokers created by [additionalBrokerFactory].
  final FutureOr<void> Function(Broker broker)? additionalDispose;
}

/// Runs contract tests for queue custom events/listeners.
void runQueueEventsContractTests({
  required String adapterName,
  required QueueEventsContractFactory factory,
  QueueEventsContractSettings settings = const QueueEventsContractSettings(),
}) {
  group('$adapterName queue events contract', () {
    Broker? broker;

    setUp(() async {
      broker = await factory.create();
    });

    tearDown(() async {
      final current = broker;
      if (current != null && factory.dispose != null) {
        await factory.dispose!(current);
      }
      broker = null;
    });

    test('emits and receives custom queue events', () async {
      final current = broker!;
      final queueName = _queueName('events');
      const eventName = 'order.created';
      final producer = QueueEventsProducer(broker: current);
      final listener = QueueEvents(
        broker: current,
        queue: queueName,
        consumerName: 'listener-${DateTime.now().microsecondsSinceEpoch}',
      );
      await listener.start();
      addTearDown(listener.close);
      await Future<void>.delayed(settings.settleDelay);

      final next = listener.on(eventName).first.timeout(settings.timeout);
      final eventId = await producer.emit(
        queueName,
        eventName,
        payload: const {'id': 'ord-1'},
      );

      final received = await next;
      expect(received.id, eventId);
      expect(received.queue, queueName);
      expect(received.name, eventName);
      expect(received.payload['id'], 'ord-1');
    });

    test('does not deliver events from other queues', () async {
      final current = broker!;
      final producer = QueueEventsProducer(broker: current);
      final queueA = _queueName('a');
      final queueB = _queueName('b');
      final listener = QueueEvents(
        broker: current,
        queue: queueA,
        consumerName: 'listener-${DateTime.now().microsecondsSinceEpoch}',
      );
      await listener.start();
      addTearDown(listener.close);
      await Future<void>.delayed(settings.settleDelay);

      final events = <QueueCustomEvent>[];
      final sub = listener.events.listen(events.add);
      addTearDown(sub.cancel);

      await producer.emit(
        queueB,
        'invoice.created',
        payload: const {'id': 'i-1'},
      );
      await Future<void>.delayed(settings.settleDelay);

      expect(events, isEmpty);
    });

    test('on(eventName) only emits matching event names', () async {
      final current = broker!;
      final producer = QueueEventsProducer(broker: current);
      final queueName = _queueName('filter');
      final listener = QueueEvents(
        broker: current,
        queue: queueName,
        consumerName: 'listener-${DateTime.now().microsecondsSinceEpoch}',
      );
      await listener.start();
      addTearDown(listener.close);
      await Future<void>.delayed(settings.settleDelay);

      final matchFuture = listener
          .on('order.completed')
          .first
          .timeout(
            settings.timeout,
          );

      await producer.emit(
        queueName,
        'order.created',
        payload: const {'id': 'ord-filter-1'},
      );
      await producer.emit(
        queueName,
        'order.completed',
        payload: const {'id': 'ord-filter-2'},
      );

      final matched = await matchFuture;
      expect(matched.name, 'order.completed');
      expect(matched.payload['id'], 'ord-filter-2');
    });

    test('preserves headers and metadata through event delivery', () async {
      final current = broker!;
      final producer = QueueEventsProducer(broker: current);
      final queueName = _queueName('headers-meta');
      final listener = QueueEvents(
        broker: current,
        queue: queueName,
        consumerName: 'listener-${DateTime.now().microsecondsSinceEpoch}',
      );
      await listener.start();
      addTearDown(listener.close);
      await Future<void>.delayed(settings.settleDelay);

      final next = listener.events.first.timeout(settings.timeout);
      await producer.emit(
        queueName,
        'invoice.settled',
        payload: const {'invoiceId': 'inv-1'},
        headers: const {'x-trace-id': 'trace-123'},
        meta: const {'tenant': 'acme'},
      );

      final received = await next;
      expect(received.headers['x-trace-id'], 'trace-123');
      expect(received.meta['tenant'], 'acme');
      expect(received.payload['invoiceId'], 'inv-1');
    });

    test(
      'fans out queue events to multiple listeners',
      () async {
        final primary = broker!;
        final secondary = factory.additionalBrokerFactory == null
            ? primary
            : await factory.additionalBrokerFactory!();
        if (!identical(primary, secondary)) {
          addTearDown(() async {
            if (factory.additionalDispose != null) {
              await factory.additionalDispose!(secondary);
            }
          });
        }

        final producer = QueueEventsProducer(broker: primary);
        final queueName = _queueName('fanout');
        const eventName = 'order.updated';
        final listenerA = QueueEvents(
          broker: primary,
          queue: queueName,
          consumerName: 'listener-a-${DateTime.now().microsecondsSinceEpoch}',
        );
        final listenerB = QueueEvents(
          broker: secondary,
          queue: queueName,
          consumerName: 'listener-b-${DateTime.now().microsecondsSinceEpoch}',
        );
        await listenerA.start();
        await listenerB.start();
        addTearDown(listenerA.close);
        addTearDown(listenerB.close);
        await Future<void>.delayed(settings.settleDelay);

        final nextA = listenerA.on(eventName).first.timeout(settings.timeout);
        final nextB = listenerB.on(eventName).first.timeout(settings.timeout);

        await producer.emit(
          queueName,
          eventName,
          payload: const {'status': 'paid'},
        );
        final received = await Future.wait<QueueCustomEvent>([nextA, nextB]);
        expect(received, hasLength(2));
        expect(received[0].payload['status'], 'paid');
        expect(received[1].payload['status'], 'paid');
      },
      skip: _skipUnless(
        settings.capabilities.verifyFanout,
        'Adapter disabled queue-event fanout capability checks.',
      ),
    );
  });
}

String _queueName(String suffix) =>
    'contract-queue-events-$suffix-'
    '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

int _counter = 0;

Object _skipUnless(bool enabled, String reason) => enabled ? false : reason;
