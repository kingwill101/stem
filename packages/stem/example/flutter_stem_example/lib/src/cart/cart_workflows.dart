import 'package:stem/stem.dart';

import 'cart_services.dart';

/// Mini-Medusa checkout flows built from Stem hosted workflows.
///
/// Medusa mapping used by this demo:
/// - Medusa `createStep` -> [HostedWorkflowContext.step] checkpoints.
/// - Medusa step compensation -> registered [HostedCompensation] handlers,
///   which run in reverse completion order after a terminal failure.
/// - Medusa nested workflows (executing one workflow from another) -> the
///   shared [packItems]/[shipParcel] step implementations below. They run as
///   checkpoints of [checkoutWorkflow] and as the full body of
///   [fulfillOrderWorkflow], so fulfillment can run inline in checkout or
///   standalone from the page, just like invoking a Medusa workflow on its
///   own or as part of another flow.
///
/// Step results are the compensation inputs: a reservation id is enough to
/// release the reservation, a charge id is enough to refund it.
class CartDemo {
  CartDemo._({
    required this.services,
    required this.checkoutWorkflow,
    required this.fulfillOrderWorkflow,
  });

  final CartServices services;
  final HostedWorkflow<Map<String, Object?>, Map<String, Object?>>
  checkoutWorkflow;
  final HostedWorkflow<Map<String, Object?>, Map<String, Object?>>
  fulfillOrderWorkflow;
}

/// Builds demo workflows bound to [services].
///
/// Like Medusa's `attachDemoWorkflows` pattern, code is reconstructed per
/// host; only data (the services instance) persists across rebuilds.
CartDemo createCartDemo(CartServices services) {
  final releaseReservation = HostedCompensation<String>(
    name: 'release-reservation',
    run: (context, reservationId) async {
      releaseReservationImpl(services, reservationId);
    },
  );
  final refundPayment = HostedCompensation<String>(
    name: 'refund-payment',
    run: (context, chargeId) async {
      refundPaymentImpl(services, chargeId);
    },
  );

  final fulfillOrder =
      HostedWorkflow<Map<String, Object?>, Map<String, Object?>>(
        name: 'cart.fulfill-order',
        run: (context, order) async {
          final packed = await context.step(
            'pack-items',
            () => packItems(services, order),
          );
          final tracking = await context.step(
            'ship-parcel',
            () => shipParcel(services, order, packed),
          );
          return {'trackingId': tracking, 'packed': packed};
        },
      );

  final checkout = HostedWorkflow<Map<String, Object?>, Map<String, Object?>>(
    name: 'cart.checkout',
    compensations: [releaseReservation, refundPayment],
    run: (context, input) async {
      final runId = context.runId;
      final cart = await context.step(
        'validate-cart',
        () => validateCart(services, input),
      );
      final reservationId = await context.step(
        'reserve-inventory',
        () => reserveInventory(services, runId, cart),
        compensation: releaseReservation,
      );
      final chargeId = await context.step(
        'charge-payment',
        () => chargePayment(services, runId, cart),
        compensation: refundPayment,
      );
      // Nested-workflow composition: the same pack/ship implementations
      // that make up `cart.fulfill-order` run here as checkout checkpoints.
      final packed = await context.step(
        'pack-items',
        () => packItems(services, {'reservationId': reservationId}),
      );
      final trackingId = await context.step(
        'ship-parcel',
        () => shipParcel(services, {'reservationId': reservationId}, packed),
      );
      return {
        'orderId': 'order-$runId',
        'reservationId': reservationId,
        'chargeId': chargeId,
        'trackingId': trackingId,
        'totalCents': cart['totalCents']!,
      };
    },
  );

  return CartDemo._(
    services: services,
    checkoutWorkflow: checkout,
    fulfillOrderWorkflow: fulfillOrder,
  );
}

Map<String, Object?> _itemsOf(Map<String, Object?> input) {
  final raw = (input['items'] as Map?)?.cast<String, Object?>() ?? {};
  return raw;
}

Map<String, int> _quantities(Map<String, Object?> input) =>
    _itemsOf(input).map((key, value) => MapEntry(key, (value as num).toInt()));

/// Reads quantities back off a checkpointed cart value (JSON round-trip).
Map<String, int> _cartQuantities(Map<String, Object?> cart) =>
    ((cart['items'] as Map).cast<String, Object?>()).map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );

/// Validates the cart and returns `{items, totalCents}`.
Map<String, Object?> validateCart(
  CartServices services,
  Map<String, Object?> input,
) {
  final items = _quantities(input);
  if (items.isEmpty || items.values.any((qty) => qty <= 0)) {
    throw ArgumentError('Cart is empty.');
  }
  for (final entry in items.entries) {
    services.product(entry.key); // Throws for unknown SKUs.
  }
  final total = services.totalCents(items);
  services.stepLog.add('validate-cart: ${items.length} lines, $total¢');
  return {'items': items, 'totalCents': total};
}

/// Reserves stock idempotently per run and returns a reservation id.
String reserveInventory(
  CartServices services,
  String runId,
  Map<String, Object?> cart,
) {
  final items = _cartQuantities(cart);
  if (services.emptyStock) {
    throw StateError('Out of stock (simulated).');
  }
  for (final entry in items.entries) {
    final onHand = services.inventory[entry.key] ?? 0;
    if (onHand < entry.value) {
      throw StateError('Only $onHand× ${entry.key} left.');
    }
  }
  for (final entry in items.entries) {
    services.inventory[entry.key] =
        services.inventory[entry.key]! - entry.value;
  }
  final id = 'res-$runId';
  services.reservations[id] = Map.of(items);
  services.stepLog.add('reserve-inventory: $id $items');
  return id;
}

void releaseReservationImpl(CartServices services, String reservationId) {
  final held = services.reservations.remove(reservationId) ?? {};
  for (final entry in held.entries) {
    services.inventory[entry.key] =
        (services.inventory[entry.key] ?? 0) + entry.value;
  }
  services.compensationLog.add('release-reservation: $reservationId restocked');
}

/// Charges the cart total and returns a charge id.
String chargePayment(
  CartServices services,
  String runId,
  Map<String, Object?> cart,
) {
  if (services.declineCard) {
    throw StateError('Card declined (simulated).');
  }
  final id = 'ch-$runId';
  services.charges.add(id);
  services.stepLog.add("charge-payment: $id ${cart['totalCents']}¢");
  return id;
}

void refundPaymentImpl(CartServices services, String chargeId) {
  services.charges.remove(chargeId);
  services.compensationLog.add('refund-payment: $chargeId');
}

/// Shared fulfillment step: also the body of `cart.fulfill-order`.
String packItems(CartServices services, Map<String, Object?> order) {
  final id = 'pack-${order['reservationId'] ?? order['orderId']}';
  services.stepLog.add('pack-items: $id');
  return id;
}

/// Shared fulfillment step: also the body of `cart.fulfill-order`.
String shipParcel(
  CartServices services,
  Map<String, Object?> order,
  String packed,
) {
  final id = 'trk-${order['reservationId'] ?? order['orderId']}';
  services.shipments.add(id);
  services.stepLog.add('ship-parcel: $id ($packed)');
  return id;
}
