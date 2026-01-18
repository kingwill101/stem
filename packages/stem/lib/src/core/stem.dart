/// Main entry point for enqueuing and managing tasks in the Stem framework.
///
/// This library provides the [Stem] class, which acts as a high-level facade
/// for producer applications. It coordinates task serialization, routing,
/// signing, and persistence during the enqueuing process.
///
/// ## Architecture Overview
///
/// ```text
/// ┌─────────────────────────────────────────────────────────┐
/// │                         Stem                            │
/// │  ┌──────────┐  ┌──────────┐  ┌───────────────────────┐  │
/// │  │  Broker  │  │ Registry │  │    Result Backend     │  │
/// │  │(publish) │  │(metadata)│  │ (tracking/results)    │  │
/// │  └────┬─────┘  └────┬─────┘  └───────────┬───────────┘  │
/// │       │             │                    │              │
/// │       ▼             ▼                    ▼              │
/// │  ┌──────────────────────────────────────────────────┐   │
/// │  │                Enqueue Pipeline                  │   │
/// │  │  • Metadata mapping   • Payload encoding         │   │
/// │  │  • Route resolution   • Signature generation     │   │
/// │  │  • Uniqueness checks  • Result tracking          │   │
/// │  └──────────────────────┬───────────────────────────┘   │
/// │                         │                               │
/// │                         ▼                               │
/// │                  (Message Broker)                       │
/// └─────────────────────────────────────────────────────────┘
/// ```
///
/// ## Key Concepts
///
/// - **Enqueuer**: The core interface for adding tasks to the system.
/// - **Broker**: Reusable interface for message delivery (e.g. Redis,
///   Postgres).
/// - **Result Backend**: Durable storage for task states and return values.
/// - **Middleware**: Interceptor chain for enqueuing and execution events.
///
/// ## Payload Encoding
///
/// [Stem] uses a registry of [TaskPayloadEncoder]s to transform complex Dart
/// objects into serializable formats for cross-isolate or cross-process
/// communication. By default, it uses [JsonTaskPayloadEncoder].
///
/// ## Task Lineage
///
/// When enqueuing tasks from within an existing task (via [TaskContext]),
/// [Stem] automatically tracks parent-child relationships and propagates
/// trace identifiers for observability.
///
/// See also:
/// - `Worker` for the consumption and execution side of the system.
/// - `TaskDefinition` for defining strongly-typed task interfaces.
library;

import 'dart:async';
import 'dart:math' as math;

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
class Stem implements TaskEnqueuer {
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

  /// Shared signal emitter for lifecycle hooks.
  static const StemSignalEmitter _signals = StemSignalEmitter(
    defaultSender: 'stem',
  );

  /// Random source used for retry jitter.
  static final math.Random _random = math.Random();

  /// Releases broker/backend resources used by this producer.
  Future<void> close() async {
    await broker.close();
    final resolved = backend;
    if (resolved != null) {
      await resolved.close();
    }
  }

  /// Enqueue a typed task using a [TaskCall] wrapper produced by a
  /// [TaskDefinition].
  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueue(
      call.name,
      args: call.encodeArgs(),
      headers: call.headers,
      options: call.resolveOptions(),
      notBefore: call.notBefore,
      meta: call.meta,
      enqueueOptions: enqueueOptions ?? call.enqueueOptions,
    );
  }

  /// Enqueue a task by name.
  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final tracer = StemTracer.instance;
    final queueOverride = enqueueOptions?.queue ?? options.queue;
    final decision = routing.resolve(
      RouteRequest(task: name, headers: headers, queue: queueOverride),
    );
    final targetName = decision.targetName;
    final basePriority = enqueueOptions?.priority ?? options.priority;
    final resolvedPriority = decision.effectivePriority(basePriority);

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
        final scopeMeta = TaskEnqueueScope.currentMeta();
        final mergedMeta = scopeMeta == null
            ? meta
            : <String, Object?>{
                ...scopeMeta,
                ...meta,
              };
        final enrichedMeta = _applyEnqueueOptionsToMeta(
          mergedMeta,
          enqueueOptions,
        );
        if (!enrichedMeta.containsKey('stem.task')) {
          enrichedMeta['stem.task'] = name;
        }
        if (options.retryPolicy != null &&
            !enrichedMeta.containsKey('stem.retryPolicy')) {
          enrichedMeta['stem.retryPolicy'] = options.retryPolicy!.toJson();
        }
        final encodedMeta = _withArgsEncoderMeta(enrichedMeta, argsEncoder);

        final scheduledAt = _resolveNotBefore(
          notBefore,
          enqueueOptions,
        );

        final maxRetries = _resolveMaxRetries(
          options,
          handler.options,
          enqueueOptions,
        );

        var envelope = Envelope(
          name: name,
          args: encodedArgs,
          id: enqueueOptions?.taskId,
          headers: encodedHeaders,
          queue: targetName,
          notBefore: scheduledAt,
          priority: resolvedPriority,
          maxRetries: maxRetries,
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
                exchange: enqueueOptions?.exchange ?? decision.queue!.exchange,
                routingKey:
                    enqueueOptions?.routingKey ?? decision.queue!.routingKey,
                priority: resolvedPriority,
                meta: _publishMeta(enqueueOptions),
              );

        await _signals.beforeTaskPublish(envelope);

        await _runEnqueueMiddleware(envelope, () async {
          await _publishWithRetry(
            envelope,
            routing: routingInfo,
            enqueueOptions: enqueueOptions,
          );
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
    /// Executes the enqueue middleware chain in order.
    Future<void> run(int index) async {
      if (index >= middleware.length) {
        await action();
        return;
      }
      await middleware[index].onEnqueue(envelope, () => run(index + 1));
    }

    await run(0);
  }

  DateTime? _resolveNotBefore(
    DateTime? notBefore,
    TaskEnqueueOptions? enqueueOptions,
  ) {
    /// Resolves not-before scheduling from enqueue overrides.
    if (enqueueOptions == null) return notBefore;
    if (enqueueOptions.eta != null) {
      return enqueueOptions.eta;
    }
    if (enqueueOptions.countdown != null) {
      return DateTime.now().add(enqueueOptions.countdown!);
    }
    return notBefore;
  }

  int _resolveMaxRetries(
    TaskOptions options,
    TaskOptions handlerOptions,
    TaskEnqueueOptions? enqueueOptions,
  ) {
    /// Determines max retries using enqueue overrides, task options, then
    /// handler defaults.
    final policyMax = enqueueOptions?.retryPolicy?.maxRetries;
    if (policyMax != null) {
      return policyMax;
    }
    final taskPolicyMax = options.retryPolicy?.maxRetries;
    if (taskPolicyMax != null) {
      return taskPolicyMax;
    }
    if (options.maxRetries != 0) {
      return options.maxRetries;
    }
    return handlerOptions.maxRetries;
  }

  Map<String, Object?> _applyEnqueueOptionsToMeta(
    Map<String, Object?> meta,
    TaskEnqueueOptions? enqueueOptions,
  ) {
    /// Maps enqueue-only settings into envelope metadata.
    final merged = Map<String, Object?>.from(meta);
    if (enqueueOptions == null) return merged;
    if (enqueueOptions.expires != null) {
      merged['stem.expiresAt'] = enqueueOptions.expires!.toIso8601String();
    }
    if (enqueueOptions.timeLimit != null) {
      merged['stem.timeLimitMs'] = enqueueOptions.timeLimit!.inMilliseconds;
    }
    if (enqueueOptions.softTimeLimit != null) {
      merged['stem.softTimeLimitMs'] =
          enqueueOptions.softTimeLimit!.inMilliseconds;
    }
    if (enqueueOptions.serializer != null) {
      merged['stem.serializer'] = enqueueOptions.serializer;
    }
    if (enqueueOptions.compression != null) {
      merged['stem.compression'] = enqueueOptions.compression;
    }
    if (enqueueOptions.ignoreResult != null) {
      merged['stem.ignoreResult'] = enqueueOptions.ignoreResult;
    }
    if (enqueueOptions.shadow != null) {
      merged['stem.shadow'] = enqueueOptions.shadow;
    }
    if (enqueueOptions.replyTo != null) {
      merged['stem.replyTo'] = enqueueOptions.replyTo;
    }
    if (enqueueOptions.retryPolicy != null) {
      merged['stem.retryPolicy'] = enqueueOptions.retryPolicy!.toJson();
    }
    if (enqueueOptions.publishConnection != null) {
      merged['stem.publishConnection'] = enqueueOptions.publishConnection;
    }
    if (enqueueOptions.producer != null) {
      merged['stem.producer'] = enqueueOptions.producer;
    }
    if (enqueueOptions.link.isNotEmpty) {
      merged['stem.link'] = _encodeTaskCalls(enqueueOptions.link);
    }
    if (enqueueOptions.linkError.isNotEmpty) {
      merged['stem.linkError'] = _encodeTaskCalls(enqueueOptions.linkError);
    }
    return merged;
  }

  List<Map<String, Object?>> _encodeTaskCalls(
    List<TaskCall<dynamic, dynamic>> calls,
  ) {
    /// Serializes linked task calls for chain/retry metadata.
    return calls
        .map(
          (call) => {
            'name': call.name,
            'args': call.encodeArgs(),
            'headers': call.headers,
            'meta': call.meta,
            'options': _encodeTaskOptions(call.resolveOptions()),
            'notBefore': call.notBefore?.toIso8601String(),
            'enqueueOptions': call.enqueueOptions?.toJson(),
          },
        )
        .toList(growable: false);
  }

  Map<String, Object?> _encodeTaskOptions(TaskOptions options) =>
      options.toJson();

  Map<String, Object?> _publishMeta(TaskEnqueueOptions? enqueueOptions) {
    /// Extracts publish-time metadata for broker adapters.
    if (enqueueOptions == null) return const {};
    final meta = <String, Object?>{};
    if (enqueueOptions.publishConnection != null) {
      meta['connection'] = enqueueOptions.publishConnection;
    }
    if (enqueueOptions.producer != null) {
      meta['producer'] = enqueueOptions.producer;
    }
    return meta;
  }

  Future<void> _publishWithRetry(
    Envelope envelope, {
    RoutingInfo? routing,
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    /// Publishes a task with optional retry policy.
    if (enqueueOptions?.retry != true) {
      await broker.publish(envelope, routing: routing);
      return;
    }

    final policy = enqueueOptions?.retryPolicy ?? const TaskRetryPolicy();
    final maxRetries = policy.maxRetries ?? 3;
    var attempt = 0;
    while (true) {
      try {
        await broker.publish(envelope, routing: routing);
        return;
      } catch (error) {
        if (attempt >= maxRetries) rethrow;
        final delay = _computeRetryDelay(policy, attempt);
        attempt += 1;
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }
    }
  }

  Duration _computeRetryDelay(TaskRetryPolicy policy, int attempt) {
    /// Computes the delay for a publish retry attempt.
    final base = policy.defaultDelay ?? Duration.zero;
    if (!policy.backoff) {
      return base;
    }
    final rawMs = base.inMilliseconds == 0
        ? 0
        : base.inMilliseconds * (1 << attempt);
    final capMs = policy.backoffMax?.inMilliseconds ?? rawMs;
    final capped = rawMs == 0 ? capMs : rawMs.clamp(0, capMs);
    if (!policy.jitter || capped == 0) {
      return Duration(milliseconds: capped);
    }
    final jitter = _random.nextInt((capped ~/ 4) + 1);
    final jittered = (capped - jitter).clamp(0, capMs);
    return Duration(milliseconds: jittered);
  }

  Future<void> _recordDuplicateAttempt(
    String taskId,
    Envelope duplicate,
  ) async {
    /// Records a deduplicated task attempt on the existing task metadata.
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
    /// Resolves the args encoder for a handler and registers it if needed.
    final encoder = handler.metadata.argsEncoder;
    payloadEncoders.register(encoder);
    return encoder ?? payloadEncoders.defaultArgsEncoder;
  }

  TaskPayloadEncoder _resolveResultEncoder(TaskHandler<Object?> handler) {
    /// Resolves the result encoder for a handler and registers it if needed.
    final encoder = handler.metadata.resultEncoder;
    payloadEncoders.register(encoder);
    return encoder ?? payloadEncoders.defaultResultEncoder;
  }

  Map<String, Object?> _encodeArgs(
    Map<String, Object?> args,
    TaskPayloadEncoder encoder,
  ) {
    /// Encodes args with the selected encoder and normalizes map typing.
    final encoded = encoder.encode(args);
    return _castArgsMap(encoded, encoder);
  }

  Map<String, Object?> _castArgsMap(
    Object? encoded,
    TaskPayloadEncoder encoder,
  ) {
    /// Ensures encoded args are a string-keyed map with object values.
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
    /// Adds the args encoder identifier into metadata.
    return {...meta, stemArgsEncoderMetaKey: encoder.id};
  }

  Map<String, String> _withArgsEncoderHeader(
    Map<String, String> headers,
    TaskPayloadEncoder encoder,
  ) {
    /// Adds the args encoder identifier into headers.
    return {...headers, stemArgsEncoderHeader: encoder.id};
  }

  Map<String, Object?> _withResultEncoderMeta(
    Map<String, Object?> meta,
    TaskPayloadEncoder encoder,
  ) {
    /// Adds the result encoder identifier into metadata.
    return {...meta, stemResultEncoderMetaKey: encoder.id};
  }

  T? _decodeTaskPayload<T extends Object?>(
    Object? payload,
    T Function(Object? payload)? decode,
  ) {
    /// Decodes a task payload using the provided callback or a cast.
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
  /// Builds the call and enqueues it with the provided [enqueuer] instance.
  Future<String> enqueueWith(TaskEnqueuer enqueuer) {
    final call = build();
    final scopeMeta = TaskEnqueueScope.currentMeta();
    if (scopeMeta == null || scopeMeta.isEmpty) {
      return enqueuer.enqueueCall(call);
    }
    final mergedMeta = Map<String, Object?>.from(scopeMeta)..addAll(call.meta);
    return enqueuer.enqueueCall(
      call.copyWith(meta: Map.unmodifiable(mergedMeta)),
    );
  }
}
