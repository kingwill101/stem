import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:stem_ecommerce_example/ecommerce.dart';

void main() {
  Directory? tempDir;
  EcommerceServer? app;
  TestClient? client;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stem-ecommerce-test-');
    app = await EcommerceServer.create(
      databasePath: p.join(tempDir!.path, 'ecommerce.sqlite'),
    );
    client = TestClient.inMemory(ShelfRequestHandler(app!.handler));
  });

  tearDown(() async {
    if (client != null) {
      await client!.close();
    }
    if (app != null) {
      await app!.close();
    }
    if (tempDir != null && tempDir!.existsSync()) {
      await tempDir!.delete(recursive: true);
    }
  });

  test('cart creation + add-to-cart workflow persists item', () async {
    final createResponse = await client!.postJson('/carts', {
      'customerId': 'cust-123',
    });
    createResponse
      ..assertStatus(201)
      ..assertJsonPath('cart.customerId', 'cust-123')
      ..assertJsonPath('cart.itemCount', 0);

    final cartId = createResponse.json('cart.id') as String;

    final addResponse = await client!.postJson('/carts/$cartId/items', {
      'sku': 'sku_tee',
      'quantity': 2,
    });
    addResponse
      ..assertStatus(200)
      ..assertJsonPath('cart.itemCount', 1)
      ..assertJsonPath('cart.totalCents', 5000);

    final addedCart = addResponse.json('cart') as Map<String, dynamic>;
    final addedItems = (addedCart['items'] as List).cast<Map>();
    expect(addedItems.first['sku'], 'sku_tee');

    final runId = addResponse.json('runId') as String;

    final runResponse = await client!.get('/runs/$runId');
    runResponse
      ..assertStatus(200)
      ..assertJsonPath('detail.run.workflow', 'ecommerce.cart.add_item')
      ..assertJsonPath('detail.run.status', 'completed');
  });

  test('checkout flow creates order and exposes run detail', () async {
    final createResponse = await client!.postJson('/carts', {
      'customerId': 'cust-checkout',
    });
    createResponse.assertStatus(201);
    final cartId = createResponse.json('cart.id') as String;

    final addOne = await client!.postJson('/carts/$cartId/items', {
      'sku': 'sku_mug',
      'quantity': 1,
    });
    addOne.assertStatus(200);

    final addTwo = await client!.postJson('/carts/$cartId/items', {
      'sku': 'sku_sticker_pack',
      'quantity': 3,
    });
    addTwo
      ..assertStatus(200)
      ..assertJsonPath('cart.itemCount', 2)
      ..assertJsonPath('cart.totalCents', 3900);

    final checkoutResponse = await client!.postJson('/checkout/$cartId', {});
    checkoutResponse
      ..assertStatus(200)
      ..assertJsonPath('order.status', 'confirmed')
      ..assertJsonPath('order.cartId', cartId)
      ..assertJsonPath('order.totalCents', 3900);

    final runId = checkoutResponse.json('runId') as String;
    final orderId = checkoutResponse.json('order.id') as String;

    final orderResponse = await client!.get('/orders/$orderId');
    orderResponse
      ..assertStatus(200)
      ..assertJsonPath('order.id', orderId);

    final orderPayload = orderResponse.json('order') as Map<String, dynamic>;
    final orderItems = (orderPayload['items'] as List).cast<Map>();
    expect(orderItems.first['sku'], 'sku_mug');

    final runResponse = await client!.get('/runs/$runId');
    runResponse
      ..assertStatus(200)
      ..assertJsonPath('detail.run.workflow', 'ecommerce.checkout')
      ..assertJsonPath('detail.run.status', 'completed');
  });

  test('ephemeral server mode works with Shelf adapter', () async {
    final ephemeral = TestClient.ephemeralServer(
      ShelfRequestHandler(app!.handler),
    );
    addTearDown(ephemeral.close);

    final health = await ephemeral.get('/health');
    health
      ..assertStatus(200)
      ..assertJsonPath('status', 'ok');
  });

  test(
    'add-to-cart workflow validates cart and catalog via database',
    () async {
      final missingCart = await client!.postJson('/carts/cart-missing/items', {
        'sku': 'sku_tee',
        'quantity': 1,
      });
      missingCart
        ..assertStatus(422)
        ..assertJsonPath('error', 'Add-to-cart workflow did not complete.');

      final createResponse = await client!.postJson('/carts', {
        'customerId': 'cust-db-checks',
      });
      final cartId = createResponse.json('cart.id') as String;

      final unknownSku = await client!.postJson('/carts/$cartId/items', {
        'sku': 'sku_missing',
        'quantity': 1,
      });
      unknownSku
        ..assertStatus(422)
        ..assertJsonPath('error', 'Add-to-cart workflow did not complete.');
    },
  );
}
