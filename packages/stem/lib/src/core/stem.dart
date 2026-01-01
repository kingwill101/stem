import 'dart:async';

import 'package:contextual/contextual.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/encoder_keys.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/retry.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/core/task_result.dart';
import 'package:stem/src/core/unique_task_coordinator.dart';
import 'package:stem/src/observability/logging.dart';
import 'package:stem/src/observability/metrics.dart';
import 'package:stem/src/observability/tracing.dart';
import 'package:stem/src/routing/routing_config.dart';
import 'package:stem/src/routing/routing_registry.dart';
import 'package:stem/src/security/signing.dart';
import 'package:stem/src/signals/emitter.dart';

/// Facade used by producer applications to enqueue tasks.
class Stem {
  /// Creates a Stem producer facade with the provided dependencies.
  Stem({
    required this.broker,
    required this.registry,
    this.backend,
    this.uniqueTaskCoordinator,
    RetryStrategy? retryStrategy,
    List<Middleware> middleware = const [],
    this.signer,
    RoutingRegistry? routing,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) : payloadEncoders = ensureTaskPayloadEncoderRegistry(
         encoderRegistry,
         resultEncoder: resultEncoder,
         argsEncoder: argsEncoder,
         additionalEncoders: additionalEncoders,
       ),
       routing = routing ?? RoutingRegistry(RoutingConfig.legacy()),
       retryStrategy = retryStrategy ?? ExponentialJitterRetryStrategy(),
       middleware = List.unmodifiable(middleware);

  /// Broker used to publish task envelopes.
  final Broker broker;

  /// Task registry used to resolve handlers and metadata.
  final TaskRegistry registry;

  /// Optional backend used for result tracking.
  final ResultBackend? backend;

  /// Coordinator used for unique task enforcement.
  final UniqueTaskCoordinator? uniqueTaskCoordinator;

  /// Retry strategy used for backoff computations.
  final RetryStrategy retryStrategy;

  /// Middleware chain invoked around enqueue/consume/execute.
  final List<Middleware> middleware;

  /// Optional payload signer used for envelope signing.
  final PayloadSigner? signer;

  /// Routing registry used to resolve queue/broadcast targets.
  final RoutingRegistry routing;

  /// Registry of payload encoders used for args/results.
  final TaskPayloadEncoderRegistry payloadEncoders;
  static const StemSignalEmitter _signals = StemSignalEmitter(
    defaultSender: 'stem',
  );

  /// Enqueue a typed task using a [TaskCall] wrapper produced by a
  /// [TaskDefinition].
  Future<String> enqueueCall<TArgs, TResult>(TaskCall<TArgs, TResult> call) {
    return enqueue(
      call.name,
      args: call.encodeArgs(),
      headers: call.headers,
      options: call.resolveOptions(),
      notBefore: call.notBefore,
      meta: call.meta,
    );
  }

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

    final handler = registry.resolve(name);
    if (handler == null) {
      throw ArgumentError.value(name, 'name', 'Task is not registered');
    }
    final metadata = handler.metadata;
    final argsEncoder = _resolveArgsEncoder(handler);
    final resultEncoder = _resolveResultEncoder(handler);

    final spanAttributes = <String, Object>{
      'stem.task': name,
      'stem.queue': targetName,
      'stem.routing.target_type': decision.isBroadcast ? 'broadcast' : 'queue',
      'stem.task.idempotent': metadata.idempotent,
    };
    if (metadata.description != null && metadata.description!.isNotEmpty) {
      spanAttributes['stem.task.description'] = metadata.description!;
    }
    if (metadata.tags.isNotEmpty) {
      spanAttributes['stem.task.tags'] = List<String>.from(metadata.tags);
    }

    return tracer.trace(
      'stem.enqueue',
      () async {
        final traceHeaders = Map<String, String>.from(headers);
        tracer.injectTraceContext(traceHeaders);
        final encodedHeaders = _withArgsEncoderHeader(
          traceHeaders,
          argsEncoder,
        );
        final encodedArgs = _encodeArgs(args, argsEncoder);
        final encodedMeta = _withArgsEncoderMeta(meta, argsEncoder);

        var envelope = Envelope(
          name: name,
          args: encodedArgs,
          headers: encodedHeaders,
          queue: targetName,
          notBefore: notBefore,
          priority: resolvedPriority,
          maxRetries: options.maxRetries,
          visibilityTimeout: options.visibilityTimeout,
          meta: encodedMeta,
        );

        if (options.unique) {
          final coordinator = uniqueTaskCoordinator;
          if (coordinator == null) {
            throw StateError(
              'Task "$name" is configured as unique but no '
              'UniqueTaskCoordinator is set on Stem.',
            );
          }
          final claim = await coordinator.acquire(
            envelope: envelope,
            options: options,
          );
          if (!claim.isAcquired) {
            final existingId = claim.existingTaskId;
            if (existingId != null) {
              stemLogger.info(
                'Unique task deduplicated',
                Context({
                  'task': name,
                  'queue': targetName,
                  'existingId': existingId,
                  'attemptedId': envelope.id,
                }),
              );
              StemMetrics.instance.increment(
                'stem.tasks.deduplicated',
                tags: {'task': name, 'queue': targetName},
              );
              await _recordDuplicateAttempt(existingId, envelope);
              return existingId;
            }
            stemLogger.warning(
              'Unique task deduplication failed to resolve existing task id',
              Context({
                'task': name,
                'queue': targetName,
                'attemptedId': envelope.id,
              }),
            );
            return envelope.id;
          }
          final expiresAt = claim.computeExpiry(DateTime.now());
          envelope = envelope.copyWith(
            meta: {
              ...envelope.meta,
              UniqueTaskMetadata.key: claim.uniqueKey,
              UniqueTaskMetadata.owner: claim.owner,
              UniqueTaskMetadata.expiresAt: expiresAt.toIso8601String(),
            },
          );
        }

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
            final queuedMeta = _withResultEncoderMeta({
              ...envelope.meta,
              'queue': targetName,
              'maxRetries': envelope.maxRetries,
            }, resultEncoder);
            await backend!.set(
              envelope.id,
              TaskState.queued,
              attempt: envelope.attempt,
              meta: queuedMeta,
            );
          }
        });

        await _signals.afterTaskPublish(envelope);

        return envelope.id;
      },
      spanKind: dotel.SpanKind.producer,
      attributes: spanAttributes,
    );
  }

  /// Waits for [taskId] to reach a terminal state and returns a typed view of
  /// the final [TaskStatus]. Requires [backend] to be configured; otherwise a
  /// [StateError] is thrown.
  Future<TaskResult<T>?> waitForTask<T extends Object?>(
    String taskId, {
    Duration? timeout,
    T Function(Object? payload)? decode,
  }) async {
    final resultBackend = backend;
    if (resultBackend == null) {
      throw StateError(
        'Stem.waitForTask requires a configured result backend.',
      );
    }
    var lastStatus = await resultBackend.get(taskId);
    if (lastStatus != null && lastStatus.state.isTerminal) {
      return TaskResult<T>(
        taskId: taskId,
        status: lastStatus,
        value: lastStatus.state == TaskState.succeeded
            ? _decodeTaskPayload(lastStatus.payload, decode)
            : null,
        rawPayload: lastStatus.payload,
      );
    }

    final completer = Completer<TaskResult<T>?>();
    late final StreamSubscription<TaskStatus> subscription;
    Timer? timer;

    Future<void> complete(TaskStatus? status, {required bool timedOut}) async {
      if (completer.isCompleted) return;
      timer?.cancel();
      await subscription.cancel();
      if (status == null) {
        completer.complete(null);
        return;
      }
      completer.complete(
        TaskResult<T>(
          taskId: taskId,
          status: status,
          value: status.state == TaskState.succeeded
              ? _decodeTaskPayload(status.payload, decode)
              : null,
          rawPayload: status.payload,
          timedOut: timedOut && !status.state.isTerminal,
        ),
      );
    }

    subscription = resultBackend
        .watch(taskId)
        .listen(
          (status) async {
            lastStatus = status;
            if (status.state.isTerminal) {
              await complete(status, timedOut: false);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!completer.isCompleted) {
              completer.completeError(error, stack);
            }
          },
        );

    if (timeout != null) {
      timer = Timer(timeout, () => complete(lastStatus, timedOut: true));
    }

    return completer.future;
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

  Future<void> _recordDuplicateAttempt(
    String taskId,
    Envelope duplicate,
  ) async {
    if (backend == null) return;
    try {
      final status = await backend!.get(taskId);
      if (status == null) return;
      final existingDuplicates = status.meta[UniqueTaskMetadata.duplicates];
      final duplicates = <Map<String, Object?>>[];
      if (existingDuplicates is List) {
        for (final entry in existingDuplicates) {
          if (entry is Map) {
            duplicates.add(entry.cast<String, Object?>());
          }
        }
      }
      duplicates.add({
        'taskId': duplicate.id,
        'timestamp': DateTime.now().toIso8601String(),
        'headers': duplicate.headers,
        'meta': duplicate.meta,
      });
      final updatedMeta = {
        ...status.meta,
        UniqueTaskMetadata.duplicates: duplicates,
      };
      await backend!.set(
        status.id,
        status.state,
        payload: status.payload,
        error: status.error,
        attempt: status.attempt,
        meta: updatedMeta,
      );
    } on Exception catch (error, stack) {
      stemLogger.warning(
        'Failed recording unique task duplicate',
        Context({
          'taskId': taskId,
          'duplicateId': duplicate.id,
          'error': error.toString(),
          'stack': stack.toString(),
        }),
      );
    }
  }

  TaskPayloadEncoder _resolveArgsEncoder(TaskHandler<Object?> handler) {
    final encoder = handler.metadata.argsEncoder;
    payloadEncoders.register(encoder);
    return encoder ?? payloadEncoders.defaultArgsEncoder;
  }

  TaskPayloadEncoder _resolveResultEncoder(TaskHandler<Object?> handler) {
    final encoder = handler.metadata.resultEncoder;
    payloadEncoders.register(encoder);
    return encoder ?? payloadEncoders.defaultResultEncoder;
  }

  Map<String, Object?> _encodeArgs(
    Map<String, Object?> args,
    TaskPayloadEncoder encoder,
  ) {
    final encoded = encoder.encode(args);
    return _castArgsMap(encoded, encoder);
  }

  Map<String, Object?> _castArgsMap(
    Object? encoded,
    TaskPayloadEncoder encoder,
  ) {
    if (encoded == null) return const {};
    if (encoded is Map<String, Object?>) {
      return Map<String, Object?>.from(encoded);
    }
    if (encoded is Map) {
      final result = <String, Object?>{};
      encoded.forEach((key, value) {
        if (key is! String) {
          throw StateError(
            'Task args encoder ${encoder.id} must use string keys, found $key',
          );
        }
        result[key] = value;
      });
      return result;
    }
    throw StateError(
      'Task args encoder ${encoder.id} must return '
      'Map<String, Object?> values, got ${encoded.runtimeType}.',
    );
  }

  Map<String, Object?> _withArgsEncoderMeta(
    Map<String, Object?> meta,
    TaskPayloadEncoder encoder,
  ) {
    return {...meta, stemArgsEncoderMetaKey: encoder.id};
  }

  Map<String, String> _withArgsEncoderHeader(
    Map<String, String> headers,
    TaskPayloadEncoder encoder,
  ) {
    return {...headers, stemArgsEncoderHeader: encoder.id};
  }

  Map<String, Object?> _withResultEncoderMeta(
    Map<String, Object?> meta,
    TaskPayloadEncoder encoder,
  ) {
    return {...meta, stemResultEncoderMetaKey: encoder.id};
  }

  T? _decodeTaskPayload<T extends Object?>(
    Object? payload,
    T Function(Object? payload)? decode,
  ) {
    if (payload == null) return null;
    if (decode != null) {
      return decode(payload);
    }
    return payload as T?;
  }
}

/// Convenience helpers for enqueuing [TaskEnqueueBuilder] instances.
extension TaskEnqueueBuilderExtension<TArgs, TResult>
    on TaskEnqueueBuilder<TArgs, TResult> {
  /// Builds the call and enqueues it with the provided [stem] instance.
  Future<String> enqueueWith(Stem stem) => stem.enqueueCall(build());
}
