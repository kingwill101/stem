import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

import 'domain/repository.dart';
import 'tasks/manual_tasks.dart';
import 'workflows/annotated_defs.dart';
import 'workflows/checkout_flow.dart';

class EcommerceServer {
  EcommerceServer._({
    required this.workflowApp,
    required this.repository,
    required Handler handler,
  }) : _handler = handler;

  final StemWorkflowApp workflowApp;
  final EcommerceRepository repository;
  final Handler _handler;

  Handler get handler => _handler;

  static Future<EcommerceServer> create({String? databasePath}) async {
    final commerceDatabasePath = await _resolveDatabasePath(databasePath);
    final stemDatabasePath = p.join(
      p.dirname(commerceDatabasePath),
      'stem_runtime.sqlite',
    );
    final repository = await EcommerceRepository.open(commerceDatabasePath);
    bindAddToCartWorkflowRepository(repository);
    final checkoutFlow = buildCheckoutFlow(repository);
    final checkoutWorkflow = checkoutWorkflowRef(checkoutFlow);

    final workflowApp = await StemWorkflowApp.fromUrl(
      'sqlite://$stemDatabasePath',
      adapters: const [StemSqliteAdapter()],
      module: stemModule,
      flows: [checkoutFlow],
      tasks: [shipmentReserveTaskHandler],
      workerConfig: StemWorkerConfig(
        queue: 'workflow',
        consumerName: 'ecommerce-worker',
        concurrency: 2,
      ),
    );

    await workflowApp.start();

    final router = Router()
      ..get('/health', (Request request) async {
        return _json(200, {
          'status': 'ok',
          'databasePath': repository.databasePath,
          'stemDatabasePath': stemDatabasePath,
          'workflows': [
            StemWorkflowDefinitions.addToCart.name,
            checkoutWorkflow.name,
          ],
        });
      })
      ..get('/catalog', (Request request) async {
        final catalog = await repository.listCatalog();
        return _json(200, {'items': catalog});
      })
      ..post('/carts', (Request request) async {
        try {
          final payload = await _readJsonMap(request);
          final customerId =
              payload['customerId']?.toString().trim().isNotEmpty == true
              ? payload['customerId']!.toString().trim()
              : 'guest';

          final cart = await repository.createCart(customerId: customerId);
          return _json(201, {'cart': cart});
        } on Object catch (error) {
          return _error(400, 'Failed to create cart.', error);
        }
      })
      ..get('/carts/<cartId>', (Request request, String cartId) async {
        final cart = await repository.getCart(cartId);
        if (cart == null) {
          return _error(404, 'Cart not found.', {'cartId': cartId});
        }
        return _json(200, {'cart': cart});
      })
      ..post('/carts/<cartId>/items', (Request request, String cartId) async {
        try {
          final payload = await _readJsonMap(request);
          final sku = payload['sku']?.toString() ?? '';
          final quantity = _toInt(payload['quantity']);

          final result = await StemWorkflowDefinitions.addToCart.startAndWait(
            workflowApp,
            params: (cartId: cartId, sku: sku, quantity: quantity),
            timeout: const Duration(seconds: 4),
          );

          if (result == null) {
            return _error(500, 'Add-to-cart workflow run not found.', {
              'runId': null,
            });
          }

          if (result.status != WorkflowStatus.completed ||
              result.value == null) {
            return _error(422, 'Add-to-cart workflow did not complete.', {
              'runId': result.runId,
              'status': result.status.name,
              'lastError': result.state.lastError,
            });
          }

          final computed = result.value!;
          final updatedCart = await repository.addItemToCart(
            cartId: cartId,
            sku: sku,
            title: computed['title']?.toString() ?? sku,
            quantity: quantity,
            unitPriceCents: _toInt(computed['unitPriceCents']),
          );

          return _json(200, {'runId': result.runId, 'cart': updatedCart});
        } on Object catch (error) {
          return _error(400, 'Failed to add item to cart.', error);
        }
      })
      ..post('/checkout/<cartId>', (Request request, String cartId) async {
        try {
          final runId = await checkoutWorkflow.call(cartId).startWith(workflowApp);

          final result = await checkoutWorkflow.waitFor(
            workflowApp,
            runId,
            timeout: const Duration(seconds: 6),
          );

          if (result == null) {
            return _error(500, 'Checkout workflow run not found.', {
              'runId': runId,
            });
          }

          if (result.status != WorkflowStatus.completed ||
              result.value == null) {
            return _error(409, 'Checkout workflow did not complete.', {
              'runId': runId,
              'status': result.status.name,
              'lastError': result.state.lastError,
            });
          }

          return _json(200, {'runId': runId, 'order': result.value});
        } on Object catch (error) {
          return _error(400, 'Failed to checkout cart.', error);
        }
      })
      ..get('/orders/<orderId>', (Request request, String orderId) async {
        final order = await repository.getOrder(orderId);
        if (order == null) {
          return _error(404, 'Order not found.', {'orderId': orderId});
        }
        return _json(200, {'order': order});
      })
      ..get('/runs/<runId>', (Request request, String runId) async {
        final detail = await workflowApp.viewRunDetail(runId);
        if (detail == null) {
          return _error(404, 'Workflow run not found.', {'runId': runId});
        }
        return _json(200, {'detail': detail.toJson()});
      });

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    return EcommerceServer._(
      workflowApp: workflowApp,
      repository: repository,
      handler: handler,
    );
  }

  Future<void> close() async {
    try {
      await workflowApp.shutdown();
    } finally {
      try {
        await repository.close();
      } finally {
        unbindAddToCartWorkflowRepository();
      }
    }
  }
}

Future<String> _resolveDatabasePath(String? path) async {
  if (path != null && path.trim().isNotEmpty) {
    return p.normalize(path);
  }

  final directory = Directory(p.join('.dart_tool', 'ecommerce'));
  await directory.create(recursive: true);
  return p.join(directory.path, 'ecommerce.sqlite');
}

Future<Map<String, Object?>> _readJsonMap(Request request) async {
  final body = await request.readAsString();
  if (body.trim().isEmpty) {
    return <String, Object?>{};
  }

  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw FormatException('Request payload must be a JSON object.');
  }

  return decoded.cast<String, Object?>();
}

Response _json(int status, Map<String, Object?> payload) {
  return Response(
    status,
    body: jsonEncode(payload),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

Response _error(int status, String message, Object? error) {
  return _json(status, {'error': message, 'details': _normalizeError(error)});
}

Object? _normalizeError(Object? error) {
  if (error == null) {
    return null;
  }
  if (error is Map<String, Object?>) {
    return error;
  }
  if (error is Map) {
    return error.cast<String, Object?>();
  }
  return error.toString();
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
