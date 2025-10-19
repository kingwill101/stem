import 'contracts.dart';
import 'envelope.dart';
import 'retry.dart';

/// Facade used by producer applications to enqueue tasks.
class Stem {
  Stem({
    required this.broker,
    required this.registry,
    this.backend,
    RetryStrategy? retryStrategy,
  }) : retryStrategy =
           retryStrategy ??
           ExponentialJitterRetryStrategy(base: const Duration(seconds: 2));

  final Broker broker;
  final TaskRegistry registry;
  final ResultBackend? backend;
  final RetryStrategy retryStrategy;

  /// Enqueue a task by name.
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
  }) async {
    final handler = registry.resolve(name);
    if (handler == null) {
      throw ArgumentError.value(name, 'name', 'Task is not registered');
    }
    final envelope = Envelope(
      name: name,
      args: args,
      headers: headers,
      queue: options.queue,
      notBefore: notBefore,
      priority: options.priority,
      maxRetries: options.maxRetries,
      visibilityTimeout: options.visibilityTimeout,
      meta: meta,
    );

    await _runEnqueueMiddleware(envelope, () async {
      await broker.publish(envelope);
      if (backend != null) {
        await backend!.set(
          envelope.id,
          TaskState.queued,
          attempt: envelope.attempt,
          meta: {
            ...meta,
            'queue': envelope.queue,
            'maxRetries': envelope.maxRetries,
          },
        );
      }
    });
    return envelope.id;
  }

  Future<void> _runEnqueueMiddleware(
    Envelope envelope,
    Future<void> Function() action,
  ) async {
    // Middleware support can be added once the pipeline infrastructure exists.
    await action();
  }
}
