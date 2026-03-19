import 'package:stem/stem.dart';

import '../domain/repository.dart';

part 'annotated_defs.stem.g.dart';

EcommerceRepository? _addToCartWorkflowRepository;

void bindAddToCartWorkflowRepository(EcommerceRepository repository) {
  _addToCartWorkflowRepository = repository;
}

void unbindAddToCartWorkflowRepository() {
  _addToCartWorkflowRepository = null;
}

EcommerceRepository get _repository {
  final repository = _addToCartWorkflowRepository;
  if (repository == null) {
    throw StateError(
      'AddToCartWorkflow repository is not bound. '
      'Call bindAddToCartWorkflowRepository(...) during startup.',
    );
  }
  return repository;
}

@WorkflowDefn(
  name: 'ecommerce.cart.add_item',
  kind: WorkflowKind.script,
  starterName: 'AddToCart',
  description: 'Validates cart item requests and computes durable pricing.',
)
class AddToCartWorkflow {
  Future<Map<String, Object?>> run(
    String cartId,
    String sku,
    int quantity,
  ) async {
    final validated = await validateInput(cartId, sku, quantity);
    final priced = await priceLineItem(cartId, sku, quantity);
    return <String, Object?>{...validated, ...priced};
  }

  @WorkflowStep(name: 'validate-input')
  Future<Map<String, Object?>> validateInput(
    String cartId,
    String sku,
    int quantity,
  ) async {
    if (cartId.trim().isEmpty) {
      throw ArgumentError.value(cartId, 'cartId', 'Cart ID must not be empty.');
    }
    if (sku.trim().isEmpty) {
      throw ArgumentError.value(sku, 'sku', 'SKU must not be empty.');
    }
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Quantity must be > 0.');
    }
    return {'cartId': cartId, 'sku': sku, 'quantity': quantity};
  }

  @WorkflowStep(name: 'price-line-item')
  Future<Map<String, Object?>> priceLineItem(
    String cartId,
    String sku,
    int quantity,
  ) async {
    return _repository.resolveLineItemForCart(
      cartId: cartId,
      sku: sku,
      quantity: quantity,
    );
  }
}

@TaskDefn(
  name: 'ecommerce.audit.log',
  options: TaskOptions(queue: 'default'),
  runInIsolate: false,
)
Future<Map<String, Object?>> logAuditEvent(
  TaskInvocationContext context,
  String event,
  String entityId,
  String detail,
) async {
  context.progress(
    1.0,
    data: {'event': event, 'entityId': entityId, 'detail': detail},
  );

  return {
    'event': event,
    'entityId': entityId,
    'detail': detail,
    'attempt': context.attempt,
  };
}
