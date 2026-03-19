import 'dart:async';

import 'package:stem/stem.dart';

FutureOr<Object?> _reserveShipmentTask(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final orderId = args['orderId']?.toString() ?? 'unknown';
  final carrier = args['carrier']?.toString() ?? 'acme-post';
  await Future<void>.delayed(const Duration(milliseconds: 25));
  context.progress(
    1.0,
    data: {
      'orderId': orderId,
      'carrier': carrier,
      'reservation': 'ship-$orderId',
    },
  );
  return {
    'orderId': orderId,
    'carrier': carrier,
    'reservationId': 'ship-$orderId',
  };
}

final TaskHandler<Object?> shipmentReserveTaskHandler =
    FunctionTaskHandler<Object?>(
      name: 'ecommerce.shipping.reserve',
      entrypoint: _reserveShipmentTask,
      options: const TaskOptions(queue: 'default'),
      runInIsolate: false,
    );
