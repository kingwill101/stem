// Queue custom event examples for documentation.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

// #region queue-events-producer-listener
Future<void> queueEventsProducerListener(Broker broker) async {
  final producer = QueueEventsProducer(broker: broker);
  final listener = QueueEvents(
    broker: broker,
    queue: 'orders',
    consumerName: 'orders-events',
  );
  await listener.start();

  final subscription = listener.on('order.created').listen((event) {
    print('Order created: ${event.payload['orderId']}');
    print('Trace id: ${event.headers['x-trace-id']}');
  });

  await producer.emitJson(
    'orders',
    'order.created',
    const _OrderCreatedEvent(orderId: 'ord-1001'),
    headers: const {'x-trace-id': 'trace-123'},
    meta: const {'tenant': 'acme'},
  );

  await Future<void>.delayed(const Duration(milliseconds: 200));
  await subscription.cancel();
  await listener.close();
}
// #endregion queue-events-producer-listener

// #region queue-events-fanout
Future<void> queueEventsFanout(Broker broker) async {
  final producer = QueueEventsProducer(broker: broker);
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

  final subscriptionA = listenerA.events.listen((event) {
    print('A saw ${event.name}');
  });
  final subscriptionB = listenerB.events.listen((event) {
    print('B saw ${event.name}');
  });

  await producer.emitJson(
    'orders',
    'order.updated',
    const _OrderUpdatedEvent(id: 'o-1'),
  );

  await Future<void>.delayed(const Duration(milliseconds: 200));
  await subscriptionA.cancel();
  await subscriptionB.cancel();
  await listenerA.close();
  await listenerB.close();
}

// #endregion queue-events-fanout

class _OrderCreatedEvent {
  const _OrderCreatedEvent({required this.orderId});

  final String orderId;

  Map<String, Object?> toJson() => {'orderId': orderId};
}

class _OrderUpdatedEvent {
  const _OrderUpdatedEvent({required this.id});

  final String id;

  Map<String, Object?> toJson() => {'id': id};
}
