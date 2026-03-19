import 'package:stem/stem.dart';

import '../domain/repository.dart';

const checkoutWorkflowName = 'ecommerce.checkout';

Flow<Map<String, Object?>> buildCheckoutFlow(EcommerceRepository repository) {
  return Flow<Map<String, Object?>>(
    name: checkoutWorkflowName,
    description: 'Converts a cart into an order and emits operational tasks.',
    metadata: const {'domain': 'commerce', 'surface': 'checkout'},
    build: (flow) {
      flow.step('load-cart', (ctx) async {
        final cartId = ctx.params['cartId']?.toString() ?? '';
        if (cartId.isEmpty) {
          throw ArgumentError('Missing required cartId parameter.');
        }

        final cart = await repository.getCart(cartId);
        if (cart == null) {
          throw StateError('Cart $cartId not found.');
        }
        return cart;
      });

      flow.step('capture-payment', (ctx) async {
        final resume = ctx.takeResumeValue<Map<String, Object?>>();
        if (resume == null) {
          ctx.sleep(
            const Duration(milliseconds: 100),
            data: {
              'phase': 'payment-authorization',
              'cartId': ctx.params['cartId'],
            },
          );
          return null;
        }

        final cartId = ctx.params['cartId']?.toString() ?? 'unknown-cart';
        return {'paymentReference': 'pay-$cartId'};
      });

      flow.step('create-order', (ctx) async {
        final cartId = ctx.params['cartId']?.toString() ?? '';
        final paymentPayload = _mapFromDynamic(ctx.previousResult);
        final paymentReference =
            paymentPayload['paymentReference']?.toString() ?? 'pay-$cartId';

        final order = await repository.checkoutCart(
          cartId: cartId,
          paymentReference: paymentReference,
        );
        return order;
      });

      flow.step('emit-side-effects', (ctx) async {
        final order = _mapFromDynamic(ctx.previousResult);
        if (order.isEmpty) {
          throw StateError(
            'create-order step did not return an order payload.',
          );
        }

        final orderId = order['id']?.toString() ?? '';
        final cartId = order['cartId']?.toString() ?? '';

        if (ctx.enqueuer != null) {
          await ctx.enqueuer!.enqueue(
            'ecommerce.audit.log',
            args: {
              'event': 'order.checked_out',
              'entityId': orderId,
              'detail': 'cart=$cartId',
            },
            options: const TaskOptions(queue: 'default'),
            meta: {
              'workflow': checkoutWorkflowName,
              'step': 'emit-side-effects',
            },
          );

          await ctx.enqueuer!.enqueue(
            'ecommerce.shipping.reserve',
            args: {'orderId': orderId, 'carrier': 'acme-post'},
            options: const TaskOptions(queue: 'default'),
            meta: {
              'workflow': checkoutWorkflowName,
              'step': 'emit-side-effects',
            },
          );
        }

        return order;
      });
    },
  );
}

Map<String, Object?> _mapFromDynamic(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  return <String, Object?>{};
}
