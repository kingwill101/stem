import 'dart:async';

import 'package:stem/stem.dart';

Future<void> main() async {
  final cleanupObserved = Completer<void>();
  var chargeCalls = 0;
  final release = HostedCompensation<String>(
    name: 'release-reservation',
    run: (context, reservationId) {
      print('Release $reservationId (${context.idempotencyKey})');
      if (!cleanupObserved.isCompleted) cleanupObserved.complete();
    },
  );
  final checkout = HostedWorkflow<String, String>(
    name: 'checkout',
    compensations: [release],
    run: (flow, orderId) async {
      final reservation = await flow.step(
        'reserve',
        () => 'reservation-$orderId',
        compensation: release,
      );
      return flow.step<String>(
        'charge',
        () {
          chargeCalls++;
          // A simulated unavailable external service, not an actual payment.
          throw StateError('Payment unavailable for $reservation');
        },
        retry: const WorkflowRetryPolicy(
          maxAttempts: 3,
          delay: Duration(milliseconds: 10),
          multiplier: 2,
        ),
      );
    },
  );
  final host = await WorkflowHost.inMemory(workflows: [checkout]);
  try {
    final run = await host.submit(checkout, 'order-42');
    try {
      await run.result.timeout(const Duration(seconds: 10));
      throw StateError('The simulated payment was expected to fail.');
    } on HostedWorkflowFailure {
      print('Payment failed after $chargeCalls attempts.');
    }
    // Failure observation precedes asynchronous cleanup. This local completer
    // only makes the demo wait to show its output; it is not persisted state.
    await cleanupObserved.future.timeout(const Duration(seconds: 5));
  } finally {
    // Draining the active cleanup task lets its journal completion commit.
    await host.close();
  }
}
