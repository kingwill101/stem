import 'package:opentelemetry/api.dart' as otel;

import '../observability/tracing.dart';
import '../routing/routing_config.dart';
import '../routing/routing_registry.dart';
import '../security/signing.dart';
import '../signals/emitter.dart';
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
    List<Middleware> middleware = const [],
    this.signer,
    RoutingRegistry? routing,
  }) : routing = routing ?? RoutingRegistry(RoutingConfig.legacy()),
       retryStrategy =
           retryStrategy ??
           ExponentialJitterRetryStrategy(base: const Duration(seconds: 2)),
       middleware = List.unmodifiable(middleware);

  final Broker broker;
  final TaskRegistry registry;
  final ResultBackend? backend;
  final RetryStrategy retryStrategy;
  final List<Middleware> middleware;
  final PayloadSigner? signer;
  final RoutingRegistry routing;
  static const StemSignalEmitter _signals = StemSignalEmitter(
    defaultSender: 'stem',
  );

  /// Enqueue a task by name.
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
  }) async {
    final tracer = StemTracer.instance;
    final decision = routing.resolve(
      RouteRequest(task: name, headers: headers, queue: options.queue),
    );
    final targetName = decision.targetName;
    final resolvedPriority = decision.effectivePriority(options.priority);

    return tracer.trace(
      'stem.enqueue',
      () async {
        final handler = registry.resolve(name);
        if (handler == null) {
          throw ArgumentError.value(name, 'name', 'Task is not registered');
        }

        final traceHeaders = Map<String, String>.from(headers);
        tracer.injectTraceContext(traceHeaders);

        Envelope envelope = Envelope(
          name: name,
          args: args,
          headers: traceHeaders,
          queue: targetName,
          notBefore: notBefore,
          priority: resolvedPriority,
          maxRetries: options.maxRetries,
          visibilityTimeout: options.visibilityTimeout,
          meta: meta,
        );
        if (signer != null) {
          envelope = await signer!.sign(envelope);
        }

        final routingInfo = decision.isBroadcast
            ? RoutingInfo.broadcast(
                channel: decision.broadcastChannel!,
                delivery: decision.broadcast!.delivery,
                meta: decision.broadcast!.metadata,
              )
            : RoutingInfo.queue(
                queue: decision.queue!.name,
                exchange: decision.queue!.exchange,
                routingKey: decision.queue!.routingKey,
                priority: resolvedPriority,
              );

        await _signals.beforeTaskPublish(envelope);

        await _runEnqueueMiddleware(envelope, () async {
          await broker.publish(envelope, routing: routingInfo);
          if (backend != null) {
            await backend!.set(
              envelope.id,
              TaskState.queued,
              attempt: envelope.attempt,
              meta: {
                ...meta,
                'queue': targetName,
                'maxRetries': envelope.maxRetries,
              },
            );
          }
        });

        await _signals.afterTaskPublish(envelope);

        return envelope.id;
      },
      spanKind: otel.SpanKind.producer,
      attributes: [
        otel.Attribute.fromString('stem.task', name),
        otel.Attribute.fromString('stem.queue', targetName),
        otel.Attribute.fromString(
          'stem.routing.target_type',
          decision.isBroadcast ? 'broadcast' : 'queue',
        ),
      ],
    );
  }

  Future<void> _runEnqueueMiddleware(
    Envelope envelope,
    Future<void> Function() action,
  ) async {
    Future<void> run(int index) async {
      if (index >= middleware.length) {
        await action();
        return;
      }
      await middleware[index].onEnqueue(envelope, () => run(index + 1));
    }

    await run(0);
  }
}
