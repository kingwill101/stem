import 'package:contextual/contextual.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/observability/logging.dart';
import 'package:stem/src/observability/metrics.dart';

/// Coordinates acknowledgements whose failure is recoverable after terminal
/// task state has been persisted.
///
/// A broker ACK can be lost after a result backend write succeeds. In that
/// case the delivery may be redelivered, but the worker must not execute the
/// handler again. Keeping this path in one component makes that guarantee
/// explicit and gives all terminal ACK failures consistent telemetry.
class WorkerAcknowledgementCoordinator {
  /// Creates an acknowledgement coordinator for [broker].
  const WorkerAcknowledgementCoordinator(this.broker);

  /// Broker used to acknowledge deliveries.
  final QueueBroker broker;

  /// Attempts to acknowledge a delivery without masking already durable task
  /// state when the broker is unavailable.
  Future<bool> tryAcknowledge(
    Delivery delivery, {
    required Envelope envelope,
    required String phase,
  }) async {
    try {
      await broker.ack(delivery);
      return true;
    } on Object catch (error, stack) {
      StemMetrics.instance.increment(
        'stem.acks.failed',
        tags: {'task': envelope.name, 'queue': envelope.queue},
      );
      stemLogger.warning(
        'Task acknowledgement failed during {phase}',
        Context({
          'phase': phase,
          'task': envelope.name,
          'id': envelope.id,
          'queue': envelope.queue,
          'error': error.toString(),
          'stack': stack.toString(),
        }),
      );
      return false;
    }
  }
}
