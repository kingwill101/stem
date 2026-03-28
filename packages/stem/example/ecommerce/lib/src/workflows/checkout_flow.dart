import 'package:stem/stem.dart';

import '../domain/repository.dart';

const checkoutWorkflowName = 'ecommerce.checkout';

WorkflowRef<String, Map<String, Object?>> checkoutWorkflowRef(
  Flow<Map<String, Object?>> flow,
) {
  return flow.ref<String>(
    encodeParams: (cartId) => <String, Object?>{'cartId': cartId},
  );
}

Flow<Map<String, Object?>> buildCheckoutFlow(EcommerceRepository repository) {
  return Flow<Map<String, Object?>>(
    name: checkoutWorkflowName,
    description: 'Converts a cart into an order and emits operational tasks.',
    metadata: const {'domain': 'commerce', 'surface': 'checkout'},
    build: (flow) {
      flow.step('load-cart', (ctx) async {
        final cartId = ctx.requiredParam<String>('cartId');

        final cart = await repository.getCart(cartId);
        if (cart == null) {
          throw StateError('Cart $cartId not found.');
        }
        return cart;
      });

      flow.step('capture-payment', (ctx) async {
        if (!ctx.sleepUntilResumed(
          const Duration(milliseconds: 100),
          data: {
            'phase': 'payment-authorization',
            'cartId': ctx.requiredParam<String>('cartId'),
          },
        )) {
          return null;
        }

        final cartId = ctx.requiredParam<String>('cartId');
        return {'paymentReference': 'pay-$cartId'};
      });

      flow.step('create-order', (ctx) async {
        final cartId = ctx.requiredParam<String>('cartId');
        final paymentPayload = ctx
            .requiredPreviousValue<Map<String, Object?>>();
        final paymentReference =
            paymentPayload['paymentReference']?.toString() ?? 'pay-$cartId';

        final order = await repository.checkoutCart(
          cartId: cartId,
          paymentReference: paymentReference,
        );
        return order;
      });

      flow.step('emit-side-effects', (ctx) async {
        final order = ctx.requiredPreviousValue<Map<String, Object?>>();

        final orderId = order['id']?.toString() ?? '';
        final cartId = order['cartId']?.toString() ?? '';

        await ctx.enqueue(
          'ecommerce.audit.log',
          args: {
            'event': 'order.checked_out',
            'entityId': orderId,
            'detail': 'cart=$cartId',
          },
          options: const TaskOptions(queue: 'default'),
          meta: {'workflow': checkoutWorkflowName, 'step': 'emit-side-effects'},
        );

        await ctx.enqueue(
          'ecommerce.shipping.reserve',
          args: {'orderId': orderId, 'carrier': 'acme-post'},
          options: const TaskOptions(queue: 'default'),
          meta: {'workflow': checkoutWorkflowName, 'step': 'emit-side-effects'},
        );

        return order;
      });
    },
  );
}
