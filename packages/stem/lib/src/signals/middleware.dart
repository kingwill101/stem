import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/signals/emitter.dart';
import 'package:stem/src/signals/payloads.dart';

/// Middleware adapter that forwards enqueue and execution lifecycle events to
/// the Stem signal dispatcher. Useful for incremental migrations where
/// existing middleware chains should emit signals without rewriting core
/// coordinator or worker logic.
class SignalMiddleware extends Middleware {
  /// Creates middleware for producer/coordinator contexts.
  SignalMiddleware.coordinator({StemSignalEmitter? emitter})
    : _emitter = emitter ?? const StemSignalEmitter(defaultSender: 'stem'),
      _workerInfoProvider = null;

  /// Creates middleware for worker contexts with a [workerInfo] provider.
  SignalMiddleware.worker({
    required WorkerInfo Function() workerInfo,
    StemSignalEmitter? emitter,
  }) : _emitter = emitter ?? const StemSignalEmitter(),
       _workerInfoProvider = workerInfo;

  final StemSignalEmitter _emitter;
  final WorkerInfo Function()? _workerInfoProvider;
  final Map<String, Envelope> _envelopes = {};

  @override
  Future<void> onEnqueue(
    Envelope envelope,
    Future<void> Function() next,
  ) async {
    await _emitter.beforeTaskPublish(envelope);
    await next();
    await _emitter.afterTaskPublish(envelope);
  }

  @override
  Future<void> onConsume(
    Delivery delivery,
    Future<void> Function() next,
  ) async {
    final workerInfo = _workerInfoProvider?.call();
    if (workerInfo != null) {
      _envelopes[delivery.envelope.id] = delivery.envelope;
      await _emitter.taskReceived(delivery.envelope, workerInfo);
    }
    await next();
  }

  @override
  Future<void> onExecute(
    TaskContext context,
    Future<void> Function() next,
  ) async {
    final workerInfoProvider = _workerInfoProvider;
    if (workerInfoProvider == null) {
      await next();
      return;
    }
    final envelope = _envelopes[context.id];
    if (envelope != null) {
      await _emitter.taskPrerun(envelope, workerInfoProvider(), context);
    }
    Object? error;
    try {
      await next();
    } catch (err) {
      error = err;
      rethrow;
    } finally {
      if (error == null) {
        _envelopes.remove(context.id);
      }
    }
  }

  @override
  Future<void> onError(
    TaskContext context,
    Object error,
    StackTrace stackTrace,
  ) async {
    final workerInfoProvider = _workerInfoProvider;
    if (workerInfoProvider != null) {
      final envelope = _envelopes.remove(context.id);
      if (envelope != null) {
        await _emitter.taskFailed(
          envelope,
          workerInfoProvider(),
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}
