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
        meta: const {PayloadCodec.versionKey: 2, 'tenant': 'acme'},
      );

      final event = await received;
      expect(event.id, eventId);
      expect(event.queue, 'orders');
      expect(event.name, 'order.created');
      expect(event.requiredPayloadValue<String>('orderId'), 'o-1');
      expect(event.headers['x-source'], 'test');
      expect(event.meta['tenant'], 'acme');
      expect(
        event.metaJson<_QueueEventMeta>(decode: _QueueEventMeta.fromJson),
        isA<_QueueEventMeta>().having(
          (value) => value.tenant,
          'tenant',
          'acme',
        ),
      );
      expect(
        event.metaVersionedJson<_QueueEventMeta>(
          version: 2,
          decode: _QueueEventMeta.fromVersionedJson,
        ),
        isA<_QueueEventMeta>().having(
          (value) => value.tenant,
          'tenant',
          'acme',
        ),
      );
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

    test(
      'emitValue publishes typed payloads through the supplied codec',
      () async {
      final listener = QueueEvents(
        broker: broker,
        queue: 'orders',
        consumerName: 'orders-listener-codec',
      );
      await listener.start();
      addTearDown(listener.close);

      final received = listener
          .on('order.codec')
          .first
          .timeout(const Duration(seconds: 5));

      final eventId = await producer.emitValue(
        'orders',
        'order.codec',
        const _QueueEventPayload(orderId: 'o-2b', status: 'codec'),
        codec: const PayloadCodec<_QueueEventPayload>.map(
          encode: _encodeQueueEventPayloadMap,
          decode: _QueueEventPayload.fromJson,
          typeName: '_QueueEventPayload',
        ),
      );

      final event = await received;
      expect(event.id, eventId);
      expect(event.requiredPayloadValue<String>('orderId'), 'o-2b');
      expect(event.requiredPayloadValue<String>('status'), 'codec');
      expect(event.requiredPayloadValue<String>('kind'), 'custom');
      expect(
        event.payloadAs<_QueueEventPayload>(
          codec: const PayloadCodec<_QueueEventPayload>.map(
            encode: _encodeQueueEventPayloadMap,
            decode: _QueueEventPayload.fromJson,
            typeName: '_QueueEventPayload',
          ),
        ),
        isA<_QueueEventPayload>()
            .having((value) => value.orderId, 'orderId', 'o-2b')
            .having((value) => value.status, 'status', 'codec'),
      );
      },
    );

    test(
      'emitVersionedJson publishes DTO payloads with a persisted schema '
      'version',
      () async {
        final listener = QueueEvents(
          broker: broker,
          queue: 'orders',
          consumerName: 'orders-listener-versioned',
        );
        await listener.start();
        addTearDown(listener.close);

        final received = listener
            .on('order.versioned')
            .first
            .timeout(const Duration(seconds: 5));

        final eventId = await producer.emitVersionedJson(
          'orders',
          'order.versioned',
          const _QueueEventPayload(orderId: 'o-3', status: 'versioned'),
          version: 2,
        );

        final event = await received;
        expect(event.id, eventId);
        expect(event.payload, {
          PayloadCodec.versionKey: 2,
          'orderId': 'o-3',
          'status': 'versioned',
        });
        expect(
          event.payloadVersionedJson<_QueueEventPayload>(
            version: 2,
            decode: _QueueEventPayload.fromVersionedJson,
          ),
          isA<_QueueEventPayload>()
              .having((value) => value.orderId, 'orderId', 'o-3')
              .having((value) => value.status, 'status', 'versioned'),
        );
      },
    );

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

  factory _QueueEventPayload.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
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

Object? _encodeQueueEventPayloadMap(_QueueEventPayload value) => {
  ...value.toJson(),
  'kind': 'custom',
};

class _QueueEventMeta {
  const _QueueEventMeta({required this.tenant});

  factory _QueueEventMeta.fromJson(Map<String, dynamic> json) {
    return _QueueEventMeta(tenant: json['tenant'] as String);
  }

  factory _QueueEventMeta.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _QueueEventMeta.fromJson(json);
  }

  final String tenant;
}
