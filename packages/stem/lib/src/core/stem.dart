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
import 'dart:io';
import 'dart:math' as math;

import 'package:contextual/contextual.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as dotel;
import 'package:stem/src/core/clock.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/encoder_keys.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/payload_codec.dart';
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

/// Shared typed task-dispatch surface used by producers, apps, and contexts.
abstract interface class TaskResultCaller implements TaskEnqueuer {
  /// Reads the latest task status by task id.
  Future<TaskStatus?> getTaskStatus(String taskId);

  /// Reads the latest group status by group id.
  Future<GroupStatus?> getGroupStatus(String groupId);

  /// Waits for a task result by task id.
  Future<TaskResult<TResult>?> waitForTask<TResult extends Object?>(
    String taskId, {
    Duration? timeout,
    TResult Function(Object? payload)? decode,
    TResult Function(Map<String, dynamic> payload)? decodeJson,
    TResult Function(Map<String, dynamic> payload, int version)?
    decodeVersionedJson,
  });
}

/// Facade used by producer applications to enqueue tasks.
class Stem implements TaskResultCaller {
  /// Creates a Stem producer facade with the provided dependencies.
  Stem({
    required this.broker,
    TaskRegistry? registry,
    this.backend,
    Iterable<TaskHandler<Object?>> tasks = const [],
    this.uniqueTaskCoordinator,
    RetryStrategy? retryStrategy,
    List<Middleware> middleware = const [],
    this.signer,
    RoutingRegistry? routing,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) : registry = _resolveTaskRegistry(registry, tasks),
       payloadEncoders = ensureTaskPayloadEncoderRegistry(
         encoderRegistry,
         resultEncoder: resultEncoder,
         argsEncoder: argsEncoder,
         additionalEncoders: additionalEncoders,
       ),
       routing = routing ?? RoutingRegistry(RoutingConfig.legacy()),
       retryStrategy = retryStrategy ?? ExponentialJitterRetryStrategy(),
       middleware = List.unmodifiable(middleware);

  static TaskRegistry _resolveTaskRegistry(
    TaskRegistry? registry,
    Iterable<TaskHandler<Object?>> tasks,
  ) {
    final resolved = registry ?? InMemoryTaskRegistry();
    tasks.forEach(resolved.register);
    return resolved;
  }

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

  @override
  Future<TaskStatus?> getTaskStatus(String taskId) async {
    final resolved = backend;
    if (resolved == null) return null;
    return resolved.get(taskId);
  }

  @override
  Future<GroupStatus?> getGroupStatus(String groupId) async {
    final resolved = backend;
    if (resolved == null) return null;
    return resolved.getGroup(groupId);
  }

  /// Enqueue a typed task using an explicit [TaskCall] transport object,
  /// typically produced by `TaskDefinition.buildCall(...)`.
  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    final definition = call.definition;
    final resolvedOptions = call.resolveOptions();
    final metadata = definition.metadata;
    return _enqueueResolved(
      name: call.name,
      args: call.encodeArgs(),
      headers: call.headers,
      options: resolvedOptions,
      fallbackOptions: definition.defaultOptions,
      notBefore: call.notBefore,
      meta: call.meta,
      enqueueOptions: enqueueOptions ?? call.enqueueOptions,
      metadata: metadata,
      argsEncoder: _resolveArgsEncoderFromMetadata(metadata),
      resultEncoder: _resolveResultEncoderFromMetadata(metadata),
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
    final handler = registry.resolve(name);
    if (handler == null) {
      throw ArgumentError.value(name, 'name', 'Task is not registered');
    }
    return _enqueueResolved(
      name: name,
      args: args,
      headers: headers,
      options: options,
      fallbackOptions: handler.options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
      metadata: handler.metadata,
      argsEncoder: _resolveArgsEncoder(handler),
      resultEncoder: _resolveResultEncoder(handler),
    );
  }

  Future<String> _enqueueResolved({
    required String name,
    required Map<String, Object?> args,
    required Map<String, String> headers,
    required TaskOptions options,
    required TaskOptions fallbackOptions,
    required DateTime? notBefore,
    required Map<String, Object?> meta,
    required TaskEnqueueOptions? enqueueOptions,
    required TaskMetadata metadata,
    required TaskPayloadEncoder argsEncoder,
    required TaskPayloadEncoder resultEncoder,
  }) async {
    final effectiveOptions = _resolveEffectiveTaskOptions(
      options,
      fallbackOptions,
    );
    final tracer = StemTracer.instance;
    final queueOverride = enqueueOptions?.queue ?? effectiveOptions.queue;
    final decision = routing.resolve(
      RouteRequest(task: name, headers: headers, queue: queueOverride),
    );
    final targetName = decision.targetName;
    final basePriority = enqueueOptions?.priority ?? effectiveOptions.priority;
    final resolvedPriority = decision.effectivePriority(basePriority);
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
    if (effectiveOptions.retryPolicy != null &&
        !enrichedMeta.containsKey('stem.retryPolicy')) {
      enrichedMeta['stem.retryPolicy'] = effectiveOptions.retryPolicy!.toJson();
    }

    final scheduledAt = _resolveNotBefore(
      notBefore,
      enqueueOptions,
    );
    final maxRetries = _resolveMaxRetries(
      effectiveOptions,
      enqueueOptions,
    );
    final taskId = enqueueOptions?.taskId ?? generateEnvelopeId();

    final spanAttributes = <String, Object>{
      'stem.task': name,
      'stem.task.id': taskId,
      'stem.task.attempt': 0,
      'stem.task.max_retries': maxRetries,
      'stem.task.priority': resolvedPriority,
      'stem.queue': targetName,
      'stem.routing.target_type': decision.isBroadcast ? 'broadcast' : 'queue',
      'stem.task.idempotent': metadata.idempotent,
    };
    if (scheduledAt != null) {
      spanAttributes['stem.task.not_before'] = scheduledAt
          .toUtc()
          .toIso8601String();
    }
    if (metadata.description != null && metadata.description!.isNotEmpty) {
      spanAttributes['stem.task.description'] = metadata.description!;
    }
    if (metadata.tags.isNotEmpty) {
      spanAttributes['stem.task.tags'] = List<String>.from(metadata.tags);
    }
    final producerHost = _safeLocalHostname();
    if (producerHost != null) {
      spanAttributes['host.name'] = producerHost;
    }
    _appendTracingMetaAttributes(spanAttributes, enrichedMeta);

    // Prefer explicit wire headers when present, but still fall back to the
    // current ambient span so in-process producers preserve parent linkage.
    final producerParentContext = tracer.extractTraceContext(
      headers,
      context: tracer.ambientContextOrNull(),
    );

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
        final encodedMeta = _withArgsEncoderMeta(enrichedMeta, argsEncoder);

        var envelope = Envelope(
          name: name,
          args: encodedArgs,
          id: taskId,
          headers: encodedHeaders,
          queue: targetName,
          notBefore: scheduledAt,
          priority: resolvedPriority,
          maxRetries: maxRetries,
          visibilityTimeout: effectiveOptions.visibilityTimeout,
          meta: encodedMeta,
        );

        if (effectiveOptions.unique) {
          final coordinator = uniqueTaskCoordinator;
          if (coordinator == null) {
            throw StateError(
              'Task "$name" is configured as unique but no '
              'UniqueTaskCoordinator is set on Stem.',
            );
          }
          final claim = await coordinator.acquire(
            envelope: envelope,
            options: effectiveOptions,
          );
          if (!claim.isAcquired) {
            final existingId = claim.existingTaskId;
            if (existingId != null) {
              stemLogger.info(
                'Unique task deduplicated',
                Context(
                  _logContext({
                    'task': name,
                    'queue': targetName,
                    'existingId': existingId,
                    'attemptedId': envelope.id,
                  }),
                ),
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
              Context(
                _logContext({
                  'task': name,
                  'queue': targetName,
                  'attemptedId': envelope.id,
                }),
              ),
            );
            return envelope.id;
          }
          final expiresAt = claim.computeExpiry(stemNow());
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
      context: producerParentContext,
      spanKind: dotel.SpanKind.producer,
      attributes: spanAttributes,
    );
  }

  TaskOptions _resolveEffectiveTaskOptions(
    TaskOptions options,
    TaskOptions fallbackOptions,
  ) {
    const defaults = TaskOptions();
    return TaskOptions(
      queue: options.queue != defaults.queue
          ? options.queue
          : fallbackOptions.queue,
      maxRetries: options.maxRetries != defaults.maxRetries
          ? options.maxRetries
          : fallbackOptions.maxRetries,
      softTimeLimit: options.softTimeLimit ?? fallbackOptions.softTimeLimit,
      hardTimeLimit: options.hardTimeLimit ?? fallbackOptions.hardTimeLimit,
      rateLimit: options.rateLimit ?? fallbackOptions.rateLimit,
      groupRateLimit: options.groupRateLimit ?? fallbackOptions.groupRateLimit,
      groupRateKey: options.groupRateKey ?? fallbackOptions.groupRateKey,
      groupRateKeyHeader:
          options.groupRateKeyHeader != defaults.groupRateKeyHeader
          ? options.groupRateKeyHeader
          : fallbackOptions.groupRateKeyHeader,
      groupRateLimiterFailureMode:
          options.groupRateLimiterFailureMode !=
              defaults.groupRateLimiterFailureMode
          ? options.groupRateLimiterFailureMode
          : fallbackOptions.groupRateLimiterFailureMode,
      unique: options.unique != defaults.unique
          ? options.unique
          : fallbackOptions.unique,
      uniqueFor: options.uniqueFor ?? fallbackOptions.uniqueFor,
      priority: options.priority != defaults.priority
          ? options.priority
          : fallbackOptions.priority,
      acksLate: options.acksLate != defaults.acksLate
          ? options.acksLate
          : fallbackOptions.acksLate,
      visibilityTimeout:
          options.visibilityTimeout ?? fallbackOptions.visibilityTimeout,
      retryPolicy: options.retryPolicy ?? fallbackOptions.retryPolicy,
    );
  }

  /// Waits for [taskId] to reach a terminal state and returns a typed view of
  /// the final [TaskStatus]. Requires [backend] to be configured; otherwise a
  /// [StateError] is thrown.
  @override
  Future<TaskResult<T>?> waitForTask<T extends Object?>(
    String taskId, {
    Duration? timeout,
    T Function(Object? payload)? decode,
    T Function(Map<String, dynamic> payload)? decodeJson,
    T Function(Map<String, dynamic> payload, int version)? decodeVersionedJson,
  }) async {
    assert(
      [decode, decodeJson, decodeVersionedJson]
              .whereType<Object>()
              .length <=
          1,
      'Specify at most one of decode, decodeJson, or decodeVersionedJson.',
    );
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
            ? _decodeTaskPayload(
                lastStatus.payload,
                decode,
                decodeJson,
                decodeVersionedJson,
              )
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
              ? _decodeTaskPayload(
                  status.payload,
                  decode,
                  decodeJson,
                  decodeVersionedJson,
                )
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

  /// Executes the enqueue middleware chain in order.
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

  /// Resolves not-before scheduling from enqueue overrides.
  DateTime? _resolveNotBefore(
    DateTime? notBefore,
    TaskEnqueueOptions? enqueueOptions,
  ) {
    if (enqueueOptions == null) return notBefore;
    if (enqueueOptions.eta != null) {
      return enqueueOptions.eta;
    }
    if (enqueueOptions.countdown != null) {
      return stemNow().add(enqueueOptions.countdown!);
    }
    return notBefore;
  }

  /// Determines max retries using enqueue overrides, task options, then
  /// handler defaults.
  int _resolveMaxRetries(
    TaskOptions options,
    TaskEnqueueOptions? enqueueOptions,
  ) {
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
    return 0;
  }

  /// Maps enqueue-only settings into envelope metadata.
  Map<String, Object?> _applyEnqueueOptionsToMeta(
    Map<String, Object?> meta,
    TaskEnqueueOptions? enqueueOptions,
  ) {
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

  /// Serializes linked task calls for chain/retry metadata.
  List<Map<String, Object?>> _encodeTaskCalls(
    List<TaskCall<dynamic, dynamic>> calls,
  ) {
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

  /// Extracts publish-time metadata for broker adapters.
  Map<String, Object?> _publishMeta(TaskEnqueueOptions? enqueueOptions) {
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

  void _appendTracingMetaAttributes(
    Map<String, Object> attributes,
    Map<String, Object?> meta,
  ) {
    final namespace = _metaString(meta, const ['stem.namespace', 'namespace']);
    if (namespace != null) {
      attributes['stem.namespace'] = namespace;
    }

    final parentTaskId = _metaString(meta, const ['stem.parentTaskId']);
    if (parentTaskId != null) {
      attributes['stem.parent_task_id'] = parentTaskId;
    }

    final rootTaskId = _metaString(meta, const ['stem.rootTaskId']);
    if (rootTaskId != null) {
      attributes['stem.root_task_id'] = rootTaskId;
    }

    final workflowRunId = _metaString(meta, const [
      'stem.workflow.runId',
      'workflow.runId',
      'stem.workflow.run_id',
    ]);
    if (workflowRunId != null) {
      attributes['stem.workflow.run_id'] = workflowRunId;
    }

    final workflowName = _metaString(meta, const [
      'stem.workflow.name',
      'workflow.name',
    ]);
    if (workflowName != null) {
      attributes['stem.workflow.name'] = workflowName;
    }

    final workflowStep = _metaString(meta, const [
      'stem.workflow.step',
      'workflow.step',
      'stem.workflow.stepName',
      'workflow.stepName',
      'stepName',
      'step',
    ]);
    if (workflowStep != null) {
      attributes['stem.workflow.step'] = workflowStep;
    }

    final workflowStepId = _metaString(meta, const [
      'stem.workflow.stepId',
      'workflow.stepId',
      'stepId',
    ]);
    if (workflowStepId != null) {
      attributes['stem.workflow.step_id'] = workflowStepId;
    }

    final workflowStepIndex = _metaInt(meta, const [
      'stem.workflow.stepIndex',
      'stem.workflow.step_index',
    ]);
    if (workflowStepIndex != null) {
      attributes['stem.workflow.step_index'] = workflowStepIndex;
    }

    final workflowIteration = _metaInt(meta, const [
      'stem.workflow.iteration',
    ]);
    if (workflowIteration != null) {
      attributes['stem.workflow.iteration'] = workflowIteration;
    }

    final workflowStepAttempt = _metaInt(meta, const [
      'stem.workflow.stepAttempt',
      'workflow.stepAttempt',
      'stepAttempt',
    ]);
    if (workflowStepAttempt != null) {
      attributes['stem.workflow.step_attempt'] = workflowStepAttempt;
    }
  }

  String? _metaString(
    Map<String, Object?> meta,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = meta[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
    return null;
  }

  int? _metaInt(
    Map<String, Object?> meta,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = meta[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  static String? _safeLocalHostname() {
    try {
      final hostname = Platform.localHostname.trim();
      return hostname.isEmpty ? null : hostname;
    } on Object {
      return null;
    }
  }

  /// Publishes a task with optional retry policy.
  Future<void> _publishWithRetry(
    Envelope envelope, {
    RoutingInfo? routing,
    TaskEnqueueOptions? enqueueOptions,
  }) async {
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

  /// Computes the delay for a publish retry attempt.
  Duration _computeRetryDelay(TaskRetryPolicy policy, int attempt) {
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

  /// Records a deduplicated task attempt on the existing task metadata.
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
        'timestamp': stemNow().toIso8601String(),
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
        Context(
          _logContext({
            'taskId': taskId,
            'duplicateId': duplicate.id,
            'error': error.toString(),
            'stack': stack.toString(),
          }),
        ),
      );
    }
  }

  Map<String, Object?> _logContext(Map<String, Object?> fields) {
    return stemContextFields(
      component: 'stem',
      subsystem: 'core',
      fields: fields,
    );
  }

  /// Resolves the args encoder for a handler and registers it if needed.
  TaskPayloadEncoder _resolveArgsEncoder(TaskHandler<Object?> handler) {
    return _resolveArgsEncoderFromMetadata(handler.metadata);
  }

  /// Resolves the result encoder for a handler and registers it if needed.
  TaskPayloadEncoder _resolveResultEncoder(TaskHandler<Object?> handler) {
    return _resolveResultEncoderFromMetadata(handler.metadata);
  }

  /// Resolves the args encoder for producer-side task metadata.
  TaskPayloadEncoder _resolveArgsEncoderFromMetadata(TaskMetadata metadata) {
    final encoder = metadata.argsEncoder;
    payloadEncoders.register(encoder);
    return encoder ?? payloadEncoders.defaultArgsEncoder;
  }

  /// Resolves the result encoder for producer-side task metadata.
  TaskPayloadEncoder _resolveResultEncoderFromMetadata(TaskMetadata metadata) {
    final encoder = metadata.resultEncoder;
    payloadEncoders.register(encoder);
    return encoder ?? payloadEncoders.defaultResultEncoder;
  }

  /// Encodes args with the selected encoder and normalizes map typing.
  Map<String, Object?> _encodeArgs(
    Map<String, Object?> args,
    TaskPayloadEncoder encoder,
  ) {
    final encoded = encoder.encode(args);
    return _castArgsMap(encoded, encoder);
  }

  /// Ensures encoded args are a string-keyed map with object values.
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

  /// Adds the args encoder identifier into metadata.
  Map<String, Object?> _withArgsEncoderMeta(
    Map<String, Object?> meta,
    TaskPayloadEncoder encoder,
  ) {
    return {...meta, stemArgsEncoderMetaKey: encoder.id};
  }

  /// Adds the args encoder identifier into headers.
  Map<String, String> _withArgsEncoderHeader(
    Map<String, String> headers,
    TaskPayloadEncoder encoder,
  ) {
    return {...headers, stemArgsEncoderHeader: encoder.id};
  }

  /// Adds the result encoder identifier into metadata.
  Map<String, Object?> _withResultEncoderMeta(
    Map<String, Object?> meta,
    TaskPayloadEncoder encoder,
  ) {
    return {...meta, stemResultEncoderMetaKey: encoder.id};
  }

  /// Decodes a task payload using the provided callback or a cast.
  T? _decodeTaskPayload<T extends Object?>(
    Object? payload,
    T Function(Object? payload)? decode,
    T Function(Map<String, dynamic> payload)? decodeJson,
    T Function(Map<String, dynamic> payload, int version)? decodeVersionedJson,
  ) {
    if (payload == null) return null;
    if (decode != null) {
      return decode(payload);
    }
    if (decodeVersionedJson != null) {
      return decodeVersionedJson(
        PayloadCodec.decodeJsonMap(payload, typeName: 'task result'),
        PayloadCodec.readPayloadVersion(payload),
      );
    }
    if (decodeJson != null) {
      return decodeJson(
        PayloadCodec.decodeJsonMap(payload, typeName: 'task result'),
      );
    }
    return payload as T?;
  }
}

Future<String> _enqueueBuiltTaskCall(
  TaskEnqueuer enqueuer,
  TaskCall<dynamic, dynamic> call, {
  TaskEnqueueOptions? enqueueOptions,
}) {
  final resolvedEnqueueOptions = enqueueOptions ?? call.enqueueOptions;
  final scopeMeta = TaskEnqueueScope.currentMeta();
  if (scopeMeta == null || scopeMeta.isEmpty) {
    return enqueuer.enqueueCall(
      call,
      enqueueOptions: resolvedEnqueueOptions,
    );
  }
  final mergedMeta = Map<String, Object?>.from(scopeMeta)..addAll(call.meta);
  return enqueuer.enqueueCall(
    call.copyWith(meta: Map.unmodifiable(mergedMeta)),
    enqueueOptions: resolvedEnqueueOptions,
  );
}

TResult _decodeTaskDefinitionResult<TArgs, TResult extends Object?>(
  TaskDefinition<TArgs, TResult> definition,
  Object? payload,
) {
  TResult? value;
  try {
    value = definition.decode(payload);
  } on Object {
    if (payload is TResult) {
      value = payload;
    } else {
      rethrow;
    }
  }
  if (value == null && null is! TResult) {
    throw StateError(
      'Task definition "${definition.name}" decoded a null result '
      'for non-nullable type $TResult.',
    );
  }
  return value as TResult;
}


/// Convenience helpers for waiting on typed task definitions.
extension TaskDefinitionExtension<TArgs, TResult extends Object?>
    on TaskDefinition<TArgs, TResult> {
  /// Enqueues this typed task definition directly with [enqueuer].
  Future<String> enqueue(
    TaskEnqueuer enqueuer,
    TArgs args, {
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return _enqueueBuiltTaskCall(
      enqueuer,
      buildCall(
        args,
        headers: headers,
        options: options,
        notBefore: notBefore,
        meta: meta,
        enqueueOptions: enqueueOptions,
      ),
      enqueueOptions: enqueueOptions,
    );
  }

  /// Enqueues this typed task definition and waits for its typed result.
  Future<TaskResult<TResult>?> enqueueAndWait(
    TaskResultCaller caller,
    TArgs args, {
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
    Duration? timeout,
  }) {
    final call = buildCall(
      args,
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
    return _enqueueBuiltTaskCall(
      caller,
      call,
      enqueueOptions: enqueueOptions,
    ).then(
      (taskId) => call.definition.waitFor(
        caller,
        taskId,
        timeout: timeout,
      ),
    );
  }

  /// Waits for [taskId] using this definition's decoding rules.
  Future<TaskResult<TResult>?> waitFor(
    TaskResultCaller caller,
    String taskId, {
    Duration? timeout,
  }) {
    return caller.waitForTask<TResult>(
      taskId,
      timeout: timeout,
      decode: (payload) => _decodeTaskDefinitionResult(this, payload),
    );
  }
}

/// Convenience helpers for waiting on typed no-arg task definitions.
extension NoArgsTaskDefinitionExtension<TResult extends Object?>
    on NoArgsTaskDefinition<TResult> {
  /// Enqueues this no-arg task definition with [enqueuer].
  Future<String> enqueue(
    TaskEnqueuer enqueuer, {
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return _enqueueBuiltTaskCall(
      enqueuer,
      asDefinition.buildCall(
        (),
        headers: headers,
        options: options,
        notBefore: notBefore,
        meta: meta,
        enqueueOptions: enqueueOptions,
      ),
      enqueueOptions: enqueueOptions,
    );
  }

  /// Waits for [taskId] using this definition's decoding rules.
  Future<TaskResult<TResult>?> waitFor(
    TaskResultCaller caller,
    String taskId, {
    Duration? timeout,
  }) {
    return asDefinition.waitFor(caller, taskId, timeout: timeout);
  }

  /// Enqueues this no-arg task definition and waits for the typed result.
  Future<TaskResult<TResult>?> enqueueAndWait(
    TaskResultCaller caller, {
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
    Duration? timeout,
  }) async {
    final taskId = await enqueue(
      caller,
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
    return waitFor(caller, taskId, timeout: timeout);
  }
}
