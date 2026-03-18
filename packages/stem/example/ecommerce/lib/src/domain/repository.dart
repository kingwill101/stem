import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:path/path.dart' as p;

import '../database/datasource.dart';
import '../database/models/models.dart';
import 'catalog.dart';

class EcommerceRepository {
  EcommerceRepository._({
    required this.databasePath,
    required DataSource dataSource,
  }) : _dataSource = dataSource;

  final String databasePath;
  final DataSource _dataSource;

  int _idCounter = 0;

  static Future<EcommerceRepository> open(String databasePath) async {
    final file = File(databasePath);
    await file.parent.create(recursive: true);

    final normalizedPath = p.normalize(databasePath);
    final dataSource = await openEcommerceDataSource(
      databasePath: normalizedPath,
    );

    final repository = EcommerceRepository._(
      databasePath: normalizedPath,
      dataSource: dataSource,
    );

    await repository._seedCatalog();

    return repository;
  }

  Future<void> close() => _dataSource.dispose();

  Future<List<Map<String, Object?>>> listCatalog() async {
    final items = await _dataSource.context
        .query<CatalogSkuModel>()
        .orderBy('sku')
        .get();

    return items
        .map(
          (item) => {
            'sku': item.sku,
            'title': item.title,
            'priceCents': item.priceCents,
            'stockAvailable': item.stockAvailable,
            'updatedAt': item.updatedAt?.toIso8601String() ?? '',
          },
        )
        .toList(growable: false);
  }

  Future<Map<String, Object?>> resolveLineItemForCart({
    required String cartId,
    required String sku,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Quantity must be > 0.');
    }

    final cart = await _dataSource.context
        .query<CartModel>()
        .whereEquals('id', cartId)
        .first();

    if (cart == null) {
      throw StateError('Cart $cartId not found.');
    }

    if (cart.status != 'open') {
      throw StateError('Cart $cartId is not open for updates.');
    }

    final item = await _dataSource.context
        .query<CatalogSkuModel>()
        .whereEquals('sku', sku)
        .first();

    if (item == null) {
      throw StateError('Unknown SKU: $sku');
    }

    final stockAvailable = item.stockAvailable;
    if (stockAvailable < quantity) {
      throw StateError(
        'Insufficient stock for $sku. Requested $quantity, available $stockAvailable.',
      );
    }

    final unitPriceCents = item.priceCents;
    return {
      'title': item.title,
      'unitPriceCents': unitPriceCents,
      'lineTotalCents': unitPriceCents * quantity,
      'stockAvailable': stockAvailable,
    };
  }

  Future<Map<String, Object?>> createCart({required String customerId}) async {
    final cartId = _nextId('cart');

    await _dataSource.context.repository<CartModel>().insert(
      CartModelInsertDto(id: cartId, customerId: customerId, status: 'open'),
    );

    final cart = await getCart(cartId);
    if (cart == null) {
      throw StateError('Failed to create cart $cartId.');
    }
    return cart;
  }

  Future<Map<String, Object?>?> getCart(String cartId) async {
    final cart = await _dataSource.context
        .query<CartModel>()
        .whereEquals('id', cartId)
        .first();
    if (cart == null) return null;

    final itemRows = await _dataSource.context
        .query<CartItemModel>()
        .whereEquals('cartId', cartId)
        .orderBy('createdAt')
        .get();

    var totalCents = 0;
    final items = itemRows
        .map((item) {
          totalCents += item.lineTotalCents;
          return <String, Object?>{
            'id': item.id,
            'sku': item.sku,
            'title': item.title,
            'quantity': item.quantity,
            'unitPriceCents': item.unitPriceCents,
            'lineTotalCents': item.lineTotalCents,
          };
        })
        .toList(growable: false);

    return {
      'id': cart.id,
      'customerId': cart.customerId,
      'status': cart.status,
      'itemCount': items.length,
      'totalCents': totalCents,
      'createdAt': cart.createdAt?.toIso8601String() ?? '',
      'updatedAt': cart.updatedAt?.toIso8601String() ?? '',
      'items': items,
    };
  }

  Future<Map<String, Object?>> addItemToCart({
    required String cartId,
    required String sku,
    required String title,
    required int quantity,
    required int unitPriceCents,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Quantity must be > 0.');
    }

    final cart = await _dataSource.context
        .query<CartModel>()
        .whereEquals('id', cartId)
        .first();
    if (cart == null) {
      throw StateError('Cart $cartId not found.');
    }
    if (cart.status != 'open') {
      throw StateError('Cart $cartId is not open for updates.');
    }

    final itemRepository = _dataSource.context.repository<CartItemModel>();
    final existing = await _dataSource.context
        .query<CartItemModel>()
        .whereEquals('cartId', cartId)
        .whereEquals('sku', sku)
        .first();

    if (existing == null) {
      await itemRepository.insert(
        CartItemModelInsertDto(
          id: _nextId('cit'),
          cartId: cartId,
          sku: sku,
          title: title,
          quantity: quantity,
          unitPriceCents: unitPriceCents,
          lineTotalCents: quantity * unitPriceCents,
        ),
      );
    } else {
      final nextQuantity = existing.quantity + quantity;
      await itemRepository.update(
        CartItemModelUpdateDto(
          quantity: nextQuantity,
          lineTotalCents: unitPriceCents * nextQuantity,
        ),
        where: CartItemModelPartial(id: existing.id),
      );
    }

    // Touch the parent cart so updatedAt reflects item mutations.
    await _dataSource.context.repository<CartModel>().update(
      const CartModelUpdateDto(status: 'open'),
      where: CartModelPartial(id: cartId),
    );

    final updated = await getCart(cartId);
    if (updated == null) {
      throw StateError('Cart $cartId was updated but could not be reloaded.');
    }

    return updated;
  }

  Future<Map<String, Object?>> checkoutCart({
    required String cartId,
    required String paymentReference,
  }) async {
    String? createdOrderId;

    await _dataSource.transaction(() async {
      final cart = await _dataSource.context
          .query<CartModel>()
          .whereEquals('id', cartId)
          .first();
      if (cart == null) {
        throw StateError('Cart $cartId not found.');
      }
      if (cart.status != 'open') {
        throw StateError('Cart $cartId is not open for checkout.');
      }

      final items = await _dataSource.context
          .query<CartItemModel>()
          .whereEquals('cartId', cartId)
          .orderBy('createdAt')
          .get();
      if (items.isEmpty) {
        throw StateError('Cart $cartId has no items to checkout.');
      }

      for (final item in items) {
        await _reserveInventory(sku: item.sku, quantity: item.quantity);
      }

      var totalCents = 0;
      for (final item in items) {
        totalCents += item.lineTotalCents;
      }

      final orderId = _nextId('ord');
      await _dataSource.context.repository<OrderModel>().insert(
        OrderModelInsertDto(
          id: orderId,
          cartId: cartId,
          customerId: cart.customerId,
          status: 'confirmed',
          totalCents: totalCents,
          paymentReference: paymentReference,
        ),
      );

      final orderItemRepository = _dataSource.context
          .repository<OrderItemModel>();
      for (final item in items) {
        await orderItemRepository.insert(
          OrderItemModelInsertDto(
            id: _nextId('ori'),
            orderId: orderId,
            sku: item.sku,
            title: item.title,
            quantity: item.quantity,
            unitPriceCents: item.unitPriceCents,
            lineTotalCents: item.lineTotalCents,
          ),
        );
      }

      await _dataSource.context.repository<CartModel>().update(
        const CartModelUpdateDto(status: 'checked_out'),
        where: CartModelPartial(id: cartId),
      );

      createdOrderId = orderId;
    });

    final orderId = createdOrderId;
    if (orderId == null) {
      throw StateError('Checkout failed to create an order.');
    }

    final order = await getOrder(orderId);
    if (order == null) {
      throw StateError('Order $orderId was created but could not be loaded.');
    }

    return order;
  }

  Future<Map<String, Object?>?> getOrder(String orderId) async {
    final order = await _dataSource.context
        .query<OrderModel>()
        .whereEquals('id', orderId)
        .first();

    if (order == null) return null;

    final itemRows = await _dataSource.context
        .query<OrderItemModel>()
        .whereEquals('orderId', orderId)
        .orderBy('createdAt')
        .get();

    final items = itemRows
        .map(
          (item) => {
            'id': item.id,
            'sku': item.sku,
            'title': item.title,
            'quantity': item.quantity,
            'unitPriceCents': item.unitPriceCents,
            'lineTotalCents': item.lineTotalCents,
          },
        )
        .toList(growable: false);

    return {
      'id': order.id,
      'cartId': order.cartId,
      'customerId': order.customerId,
      'status': order.status,
      'totalCents': order.totalCents,
      'paymentReference': order.paymentReference,
      'createdAt': order.createdAt?.toIso8601String() ?? '',
      'updatedAt': order.updatedAt?.toIso8601String() ?? '',
      'items': items,
    };
  }

  Future<void> _reserveInventory({
    required String sku,
    required int quantity,
  }) async {
    final model = await _dataSource.context
        .query<CatalogSkuModel>()
        .whereEquals('sku', sku)
        .first();

    if (model == null) {
      throw StateError('SKU $sku not found in catalog.');
    }

    final available = model.stockAvailable;
    if (available < quantity) {
      throw StateError(
        'Insufficient stock for $sku. Requested $quantity, available $available.',
      );
    }

    await _dataSource.context.repository<CatalogSkuModel>().update(
      CatalogSkuModelUpdateDto(stockAvailable: available - quantity),
      where: CatalogSkuModelPartial(sku: sku),
    );
  }

  Future<void> _seedCatalog() async {
    final existing = await _dataSource.context
        .query<CatalogSkuModel>()
        .limit(1)
        .first();
    if (existing != null) return;

    final repository = _dataSource.context.repository<CatalogSkuModel>();
    for (final sku in defaultCatalog) {
      await repository.insert(
        CatalogSkuModelInsertDto(
          sku: sku.sku,
          title: sku.title,
          priceCents: sku.priceCents,
          stockAvailable: sku.initialStock,
        ),
      );
    }
  }

  String _nextId(String prefix) {
    _idCounter += 1;
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return '$prefix-$micros-$_idCounter';
  }
}
