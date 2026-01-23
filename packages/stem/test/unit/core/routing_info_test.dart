import 'package:stem/src/core/envelope.dart';
import 'package:test/test.dart';

void main() {
  test('RoutingInfo serializes and parses queue routes', () {
    final routing = RoutingInfo.queue(
      queue: 'default',
      exchange: 'ex',
      routingKey: 'rk',
      priority: 2,
      meta: const {'foo': 'bar'},
    );

    final json = routing.toJson();
    final parsed = RoutingInfo.fromJson(json);

    expect(parsed.type, RoutingTargetType.queue);
    expect(parsed.queue, 'default');
    expect(parsed.exchange, 'ex');
    expect(parsed.routingKey, 'rk');
    expect(parsed.priority, 2);
    expect(parsed.meta['foo'], 'bar');
  });

  test('RoutingInfo parses broadcast routes', () {
    final routing = RoutingInfo.broadcast(channel: 'alerts');
    final parsed = RoutingInfo.fromJson(routing.toJson());

    expect(parsed.type, RoutingTargetType.broadcast);
    expect(parsed.broadcastChannel, 'alerts');
    expect(parsed.delivery, 'at-least-once');
    expect(parsed.isBroadcast, isTrue);
  });

  test('RoutingInfo queue routes are not broadcast', () {
    final routing = RoutingInfo.queue(queue: 'default');
    expect(routing.isBroadcast, isFalse);
  });

  test('Delivery defaults routing info from envelope', () {
    final envelope = Envelope(
      name: 'demo.route',
      args: const {},
      queue: 'priority',
      priority: 5,
    );

    final delivery = Delivery(
      envelope: envelope,
      receipt: 'receipt',
      leaseExpiresAt: null,
    );

    expect(delivery.route.queue, 'priority');
    expect(delivery.route.priority, 5);
  });
}
