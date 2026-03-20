import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('QueueEvents', () {
    late InMemoryBroker broker;
    late QueueEventsProducer producer;

    setUp(() {
      broker = InMemoryBroker(
        namespace: 'queue-events-${DateTime.now().microsecondsSinceEpoch}',
      );
      producer = QueueEventsProducer(broker: broker);
    });

    tearDown(() async {
      await broker.close();
    });

    test('receives custom events for the subscribed queue', () async {
      final listener = QueueEvents(
        broker: broker,
        queue: 'orders',
        consumerName: 'orders-listener',
      );
      await listener.start();
      addTearDown(listener.close);

      final received = listener
          .on('order.created')
          .first
          .timeout(
            const Duration(seconds: 5),
          );

      final eventId = await producer.emit(
        'orders',
        'order.created',
        payload: const {'orderId': 'o-1'},
        headers: const {'x-source': 'test'},
        meta: const {'tenant': 'acme'},
      );

      final event = await received;
      expect(event.id, eventId);
      expect(event.queue, 'orders');
      expect(event.name, 'order.created');
      expect(event.requiredPayloadValue<String>('orderId'), 'o-1');
      expect(event.headers['x-source'], 'test');
      expect(event.meta['tenant'], 'acme');
    });

    test('ignores events from other queues', () async {
      final listener = QueueEvents(
        broker: broker,
        queue: 'orders',
        consumerName: 'orders-listener',
      );
      await listener.start();
      addTearDown(listener.close);

      final events = <QueueCustomEvent>[];
      final sub = listener.events.listen(events.add);
      addTearDown(sub.cancel);

      await producer.emit(
        'billing',
        'invoice.created',
        payload: const {'invoiceId': 'i-1'},
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(events, isEmpty);
    });

    test('fans out to multiple listeners on the same queue', () async {
      final listenerA = QueueEvents(
        broker: broker,
        queue: 'orders',
        consumerName: 'orders-a',
      );
      final listenerB = QueueEvents(
        broker: broker,
        queue: 'orders',
        consumerName: 'orders-b',
      );
      await listenerA.start();
      await listenerB.start();
      addTearDown(listenerA.close);
      addTearDown(listenerB.close);

      final firstA = listenerA
          .on('order.updated')
          .first
          .timeout(
            const Duration(seconds: 5),
          );
      final firstB = listenerB
          .on('order.updated')
          .first
          .timeout(
            const Duration(seconds: 5),
          );

      await producer.emit(
        'orders',
        'order.updated',
        payload: const {'orderId': 'o-1', 'status': 'paid'},
      );

      final results = await Future.wait<QueueCustomEvent>([firstA, firstB]);
      expect(results, hasLength(2));
      expect(results[0].requiredPayloadValue<String>('status'), 'paid');
      expect(results[1].requiredPayloadValue<String>('status'), 'paid');
    });

    test('emitJson publishes DTO payloads without a manual map', () async {
      final listener = QueueEvents(
        broker: broker,
        queue: 'orders',
        consumerName: 'orders-listener',
      );
      await listener.start();
      addTearDown(listener.close);

      final received = listener
          .on('order.shipped')
          .first
          .timeout(const Duration(seconds: 5));

      final eventId = await producer.emitJson(
        'orders',
        'order.shipped',
        const _QueueEventPayload(orderId: 'o-2', status: 'shipped'),
      );

      final event = await received;
      expect(event.id, eventId);
      expect(event.requiredPayloadValue<String>('orderId'), 'o-2');
      expect(event.payloadValueOr<String>('status', 'pending'), 'shipped');
      expect(
        event.payloadJson<_QueueEventPayload>(
          decode: _QueueEventPayload.fromJson,
        ),
        isA<_QueueEventPayload>()
            .having((value) => value.orderId, 'orderId', 'o-2')
            .having((value) => value.status, 'status', 'shipped'),
      );
    });

    test('validates queue and event names', () async {
      expect(
        () => producer.emit('', 'evt'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => producer.emit('queue', '   '),
        throwsA(isA<ArgumentError>()),
      );
      final listener = QueueEvents(broker: broker, queue: 'queue');
      expect(
        () => listener.on(''),
        throwsA(isA<ArgumentError>()),
      );
      await listener.close();
    });
  });
}

class _QueueEventPayload {
  const _QueueEventPayload({
    required this.orderId,
    required this.status,
  });

  factory _QueueEventPayload.fromJson(Map<String, dynamic> json) {
    return _QueueEventPayload(
      orderId: json['orderId'] as String,
      status: json['status'] as String,
    );
  }

  final String orderId;
  final String status;

  Map<String, Object?> toJson() => {
    'orderId': orderId,
    'status': status,
  };
}
