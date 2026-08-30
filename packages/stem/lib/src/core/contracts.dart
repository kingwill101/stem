Warning: truncated output (original token count: 34467)
Total output lines: 4359

/// Core interfaces and data structures for the Stem framework.
///
/// This library defines the fundamental building blocks of Stem, including
/// the [Broker], [ResultBackend], and [TaskRegistry] interfaces. It also
/// contains common DTOs used throughout the system.
///
/// ## Key Interfaces
///
/// - **[Broker]**: Responsible for asynchronous task delivery. Implementations
///   exist for Redis, Postgres, SQS, etc.
/// - **[ResultBackend]**: Persists task state, results, and workflow progress.
/// - **[TaskRegistry]**: Maps task names to their implementation handlers.
/// - **[TaskHandler]**: The logic responsible for executing a specific task.
///
/// ## Data Structures
///
/// - **[Envelope]**: The physical unit of work sent between processes.
/// - **[TaskStatus]**: A point-in-time record of a task's lifecycle state.
/// - **[Delivery]**: A message received from a broker, including lease and
///   routing information.
///
/// ## Lifecycle Enums
///
/// - **[TaskState]**: Represents the different stages of a task (queued,
///   running, succeeded, failed, etc).
/// - `WorkerShutdownMode`: Controls how the worker terminates.
///
/// See also:
/// - `Stem` for the enqueuing facade.
/// - `Worker` for the execution runtime.
library;

import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/payload_map.dart';
import 'package:stem/src/core/task_invocation.dart';
import 'package:stem/src/core/task_payload_encoder.dart';
import 'package:stem/src/observability/heartbeat.dart';
import 'package:stem/src/scheduler/schedule_spec.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';

/// Subscription describing the queues and broadcast channels a worker should
/// consume from.
class RoutingSubscription {
  /// Creates a new [RoutingSubscription] instance.
  RoutingSubscription({
    required List<String> queues,
    List<String>? broadcastChannels,
  }) : queues = List.unmodifiable(
         queues.map((queue) => queue.trim()).where((queue) => queue.isNotEmpty),
       ),
       broadcastChannels = List.unmodifiable(
         (broadcastChannels ?? const <String>[])
             .map((channel) => channel.trim())
             .where((channel) => channel.isNotEmpty),
       ) {
    if (this.queues.isEmpty && this.broadcastChannels.isEmpty) {
      throw ArgumentError(
        'RoutingSubscription must include at least one queue '
        'or broadcast channel.',
      );
    }
  }

  /// Creates a [RoutingSubscription] for a single queue.
  factory RoutingSubscription.singleQueue(String queue) {
    final trimmed = queue.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(queue, 'queue', 'Queue name must not be empty');
    }
    return RoutingSubscription(queues: [trimmed]);
  }

  /// Canonical queue names included in this subscription.
  final List<String> queues;

  /// Broadcast channels to join.
  final List<String> broadcastChannels;

  /// Helper that expands the subscription into queue names, falling back to
  /// the provided [defaultQueue] when the subscription was created via
  /// [RoutingSubscription.singleQueue].
  List<String> resolveQueues(String defaultQueue) {
    if (queues.isEmpty) return [defaultQueue];
    return queues;
  }
}

/// Delivery guarantee advertised by a broker adapter.
enum BrokerDeliveryGuarantee {
  /// A delivery may be observed more than once after crashes or lease loss.
  atLeastOnce,

  /// A delivery is removed before handler execution and may be lost on crash.
  atMostOnce,

  /// The adapter does not declare a delivery guarantee.
  unknown,
}

/// Runtime-declared capabilities of a broker adapter.
///
/// This is intentionally additive to the [Broker] contract. Existing
/// adapters can continue implementing the legacy getters while callers use a
/// single snapshot when deciding whether to expose optional operations.
class BrokerCapabilities {
  /// Creates a broker capability snapshot.
  const BrokerCapabilities({
    required this.supportsDelayedDelivery,
    required this.supportsPriorityOrdering,
    this.deliveryGuarantee = BrokerDeliveryGuarantee.unknown,
    this.supportsBroadcastFanout = false,
    this.supportsQueueInspection = false,
    this.supportsLeaseExtension = false,
    this.supportsDeadLettering = false,
    this.supportsDeadLetterReplay = false,
  });

  /// Whether the adapter supports broker-native delayed delivery.
  final bool supportsDelayedDelivery;

  /// Delivery guarantee callers can rely on during worker crashes.
  final BrokerDeliveryGuarantee deliveryGuarantee;

  /// Whether priority ordering is part of the adapter's delivery contract.
  final bool supportsPriorityOrdering;

  /// Whether one published broadcast message is delivered to each subscriber.
  final bool supportsBroadcastFanout;

  /// Whether pending and in-flight queue counts are available.
  final bool supportsQueueInspection;

  /// Whether an active delivery lease can be extended.
  final bool supportsLeaseExtension;

  /// Whether failed deliveries can be retained in a dead-letter store.
  final bool supportsDeadLettering;

  /// Whether dead-letter entries can be replayed into an active queue.
  final bool supportsDeadLetterReplay;
}

/// Minimal transport contract used by producers and one-shot schedulers.
///
/// Event-driven runtimes can implement this contract without pretending to
/// own a consumer stream or acknowledgement lifecycle.
abstract interface class TaskPublisher {
  /// Publishes the given [envelope] using [routing] metadata when provided.
  ///
  /// When [routing] is omitted, brokers MUST fall back to [Envelope.queue] and
  /// existing semantics.
  Future<void> publish(Envelope envelope, {RoutingInfo? routing});
}

/// Optional lifecycle capability for publishers that own disposable
/// resources such as sockets or connection pools.
// ignore: one_member_abstracts
abstract interface class TaskPublisherLifecycle {
  /// Releases resources held by the publisher.
  Future<void> close();
}

/// Core queue operations required to publish and consume task deliveries.
///
/// Producer-only and event-driven integrations should implement
/// [TaskPublisher]. Long-lived workers use this broader delivery contract.
/// [Broker] remains the compatibility facade while optional operational
/// capabilities are migrated to the interfaces below.
abstract interface class QueueBroker
    implements TaskPublisher, TaskPublisherLifecycle {
  /// Returns a stream of deliveries based on the supplied [subscription].
  ///
  /// The [prefetch] parameter specifies the number of messages to prefetch.
  /// [consumerGroup] and [consumerName] can be used for consumer
  /// identification.
  Stream<Delivery> consume(
    RoutingSubscription subscription, {
    int prefetch = 1,
    String? consumerGroup,
    String? consumerName,
  });

  /// Acknowledges the [delivery], confirming successful processing.
  Future<void> ack(Delivery delivery);

  /// Negatively acknowledges the [delivery].
  ///
  /// If [requeue] is true, the message is requeued for retry.
  Future<void> nack(Delivery delivery, {bool requeue = true});

  /// Releases resources held by the transport.
  Future<void> close();
}

/// Optional broker capability for extending active delivery leases.
// ignore: one_member_abstracts
abstract interface class LeaseBroker {
  /// Extends the lease for the [delivery] by [by].
  Future<void> extendLease(Delivery delivery, Duration by);
}

/// Optional broker capability for queue-depth inspection.
abstract interface class InspectableBroker {
  /// Returns the number of pending messages for [queue], if supported.
  Future<int?> pendingCount(String queue);

  /// Returns the number of in-flight messages for [queue], if supported.
  Future<int?> inflightCount(String queue);
}

/// Optional broker capability for dead-letter inspection and replay.
abstract interface class DeadLetterBroker {
  /// Moves a delivery to the dead-letter store.
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  });

  /// Lists dead letter queue entries for [queue].
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  });

  /// Retrieves a single dead letter entry by envelope [id].
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id);

  /// Replays dead letter entries back onto the active queue.
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  });

  /// Removes dead letter entries from [queue].
  Future<int> purgeDeadLetters(String queue, {DateTime? since, int? limit});
}

/// Abstract broker compatibility facade implemented by queue adapters.
///
/// New adapters should implement [QueueBroker] plus only the optional
/// capability interfaces they actually support. Existing adapters may
/// continue implementing this broader contract during the migration period.
/// Since: 0.1.0
abstract class Broker implements QueueBroker {
  /// Sends the [delivery] to the dead letter queue.
  ///
  /// [reason] provides the reason for dead lettering, and [meta] additional
  /// data.
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) => throw UnsupportedError('Dead-lettering is not supported.');

  /// Removes all messages from the [queue].
  Future<void> purge(String queue) =>
      throw UnsupportedError('Queue purging is not supported.');

  /// Extends the lease for the [delivery] by the [by] duration.
  Future<void> extendLease(Delivery delivery, Duration by) =>
      throw UnsupportedError('Lease extension is not supported.');

  /// Returns the number of pending messages for [queue], if supported.
  Future<int?> pendingCount(String queue) async => null;

  /// Returns the number of in-flight messages for [queue], if supported.
  Future<int?> inflightCount(String queue) async => null;

  /// Whether this broker supports delayed message delivery.
  bool get supportsDelayed;

  /// Whether this broker supports message priorities.
  bool get supportsPriority;

  /// Lists dead letter queue entries for [queue], returning up to [limit]
  /// results starting at [offset]. Entries are typically ordered from newest
  /// to oldest unless documented otherwise by the implementation.
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) => throw UnsupportedError('Dead-letter inspection is not supported.');

  /// Retrieves a single dead letter entry by envelope [id], or `null` if not
  /// found.
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) =>
      throw UnsupportedError('Dead-letter inspection is not supported.');

  /// Replays at most [limit] dead letter entries back onto the active queue.
  ///
  /// When [since] is provided, only entries with a `deadAt` greater than or
  /// equal to the timestamp are considered. If [delay] is specified, replayed
  /// envelopes are scheduled with the provided delay. When [dryRun] is `true`,
  /// the method MUST NOT modify broker state and instead return the entries
  /// that would have been replayed.
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  }) => throw UnsupportedError('Dead-letter replay is not supported.');

  /// Removes dead letter entries from [queue].
  ///
  /// When [since] is provided, only entries with `deadAt` greater than or equal
  /// to the timestamp must be removed. When [limit] is set, at most that many
  /// entries are purged. Returns the number of entries removed.
  Future<int> purgeDeadLetters(
    String queue, {
    DateTime? since,
    int? limit,
  }) => throw UnsupportedError('Dead-letter purging is not supported.');

  /// Releases any resources held by the broker.
  @override
  Future<void> close() async {}
}

/// Optional provider interface for adapters with capability declarations that
/// are more precise than the legacy [Broker] getters.
abstract interface class BrokerCapabilitiesProvider {
  /// Returns the adapter's optional-operation capabilities.
  BrokerCapabilities get capabilities;
}

/// Resolves capabilities without making [Broker] implementations add a new
/// required member. External adapters therefore remain source-compatible and
/// still receive a useful snapshot from the legacy getters.
extension BrokerCapabilitiesExtension on Broker {
  /// Returns the adapter's optional-operation capabilities.
  BrokerCapabilities get capabilities {
    if (this is BrokerCapabilitiesProvider) {
      return (this as BrokerCapabilitiesProvider).capabilities;
    }
    return BrokerCapabilities(
      supportsDelayedDelivery: supportsDelayed,
      supportsPriorityOrdering: supportsPriority,
    );
  }
}

/// Resolves capabilities for code that accepts the narrow [QueueBroker] type.
///
/// Queue-only adapters without a capability provider report only the
/// operations guaranteed by [QueueBroker]. This avoids making optional
/// operations appear available merely because the caller received a transport
/// through the narrow interface.
extension QueueBrokerCapabilitiesExtension on QueueBroker {
  /// Returns the adapter's optional-operation capabilities.
  BrokerCapabilities get capabilities {
    if (this is BrokerCapabilitiesProvider) {
      return (this as BrokerCapabilitiesProvider).capabilities;
    }
    if (this is Broker) return (this as Broker).capabilities;
    return const BrokerCapabilities(
      supportsDelayedDelivery: false,
      supportsPriorityOrdering: false,
    );
  }
}

/// Optional operations for code that accepts the narrow [QueueBroker] type.
///
/// The extension first uses an explicit capability interface, then falls back
/// to the legacy [Broker] facade. This preserves existing adapters while
/// allowing new queue-only adapters to omit unsupported operations entirely.
extension QueueBrokerOptionalOperations on QueueBroker {
  /// Extends a delivery lease when the adapter supports leases.
  Future<void> extendLease(Delivery delivery, Duration by) {
    if (this is LeaseBroker) {
      return (this as LeaseBroker).extendLease(delivery, by);
    }
    if (this is Broker) {
      return (this as Broker).extendLease(delivery, by);
    }
    throw UnsupportedError('Lease extension is not supported.');
  }

  /// Sends a delivery to the dead-letter store when supported.
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  }) {
    if (this is DeadLetterBroker) {
      return (this as DeadLetterBroker).deadLetter(
        delivery,
        reason: reason,
        meta: meta,
      );
    }
    if (this is Broker) {
      return (this as Broker).deadLetter(
        delivery,
        reason: reason,
        meta: meta,
      );
    }
    throw UnsupportedError('Dead-lettering is not supported.');
  }

  /// Removes all messages from a queue when supported.
  Future<void> purge(String queue) {
    if (this is Broker) return (this as Broker).purge(queue);
    throw UnsupportedError('Queue purging is not supported.');
  }

  /// Returns a pending queue count when supported.
  Future<int?> pendingCount(String queue) {
    if (this is InspectableBroker) {
      return (this as InspectableBroker).pendingCount(queue);
    }
    if (this is Broker) return (this as Broker).pendingCount(queue);
    return Future<int?>.value();
  }

  /// Returns an in-flight queue count when supported.
  Future<int?> inflightCount(String queue) {
    if (this is InspectableBroker) {
      return (this as InspectableBroker).inflightCount(queue);
    }
    if (this is Broker) return (this as Broker).inflightCount(queue);
    return Future<int?>.value();
  }

  /// Lists dead-letter entries when the adapter supports inspection.
  Future<DeadLetterPage> listDeadLetters(
    String queue, {
    int limit = 50,
    int offset = 0,
  }) {
    if (this is DeadLetterBroker) {
      return (this as DeadLetterBroker).listDeadLetters(
        queue,
        limit: limit,
        offset: offset,
      );
    }
    if (this is Broker) {
      return (this as Broker).listDeadLetters(
        queue,
        limit: limit,
        offset: offset,
      );
    }
    throw UnsupportedError('Dead-letter inspection is not supported.');
  }

  /// Retrieves one dead-letter entry when supported.
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id) {
    if (this is DeadLetterBroker) {
      return (this as DeadLetterBroker).getDeadLetter(queue, id);
    }
    if (this is Broker) return (this as Broker).getDeadLetter(queue, id);
    throw UnsupportedError('Dead-letter inspection is not supported.');
  }

  /// Replays dead-letter entries when supported.
  Future<DeadLetterReplayResult> replayDeadLetters(
    String queue, {
    int limit = 50,
    DateTime? since,
    Duration? delay,
    bool dryRun = false,
  }) {
    if (this is DeadLetterBroker) {
      return (this as DeadLetterBroker).replayDeadLetters(
        queue,
        limit: limit,
        since: since,
        delay: delay,
        dryRun: dryRun,
      );
    }
    if (this is Broker) {
      return (this as Broker).replayDeadLetters(
        queue,
        limit: limit,
        since: since,
        delay: delay,
        dryRun: dryRun,
      );
    }
    throw UnsupportedError('Dead-letter replay is not supported.');
  }

  /// Purges dead-letter entries when supported.
  Future<int> purgeDeadLetters(
    String queue, {
    DateTime? since,
    int? limit,
  }) {
    if (this is DeadLetterBroker) {
      return (this as DeadLetterBroker).purgeDeadLetters(
        queue,
        since: since,
        limit: limit,
      );
    }
    if (this is Broker) {
      return (this as Broker).purgeDeadLetters(
        queue,
        since: since,
        limit: limit,
      );
    }
    throw UnsupportedError('Dead-letter purging is not supported.');
  }
}

/// Logical task status across enqueue, running, success, failure states.
enum TaskState {
  /// Task is queued and awaiting execution.
  queued,

  /// Task is currently executing.
  running,

  /// Task completed successfully.
  succeeded,

  /// Task failed during execution.
  failed,

  /// Task was retried and is pending another attempt.
  retried,

  /// Task was cancelled before completion.
  cancelled,
}

/// Helpers for reasoning about task lifecycle states.
extension TaskStateX on TaskState {
  /// Whether this state is terminal (no further transitions expected).
  bool get isTerminal =>
      this == TaskState.succeeded ||
      this == TaskState.failed ||
      this == TaskState.cancelled;
}

/// Canonical task record stored in the result backend.
class TaskStatus {
  /// Creates a task status snapshot.
  TaskStatus({
    required this.id,
    required this.state,
    required this.attempt,
    this.payload,
    this.error,
    Map<String, Object?>? meta,
  }) : meta = Map.unmodifiable(meta ?? const {});

  /// Builds a status snapshot from persisted JSON.
  factory TaskStatus.fromJson(Map<String, Object?> json) {
    return TaskStatus(
      id: json['id']! as String,
      state: TaskState.values.firstWhere(
        (value) => value.name == json['state'],
        orElse: () => TaskState.queued,
      ),
      payload: json['payload'],
      error: json['error'] != null
          ? TaskError.fromJson((json['error']! as Map).cast<String, Object?>())
          : null,
      meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
      attempt: (json['attempt'] as num?)?.toInt() ?? 0,
    );
  }

  /// The unique identifier for this task status.
  final String id;

  /// The current state of this task.
  final TaskState state;

  /// The payload associated with this task, if any.
  final Object? payload;

  /// Returns the decoded payload value, or `null` when no payload is present.
  ///
  /// When [codec] is supplied, the stored durable payload is decoded through
  /// that codec before being returned.
  T? payloadValue<T>({PayloadCodec<T>? codec}) {
    final stored = payload;
    if (stored == null) return null;
    if (codec != null) {
      return codec.decode(stored);
    }
    return stored as T;
  }

  /// Decodes the entire payload as a typed DTO with [codec].
  T? payloadAs<T>({required PayloadCodec<T> codec}) {
    final stored = payload;
    if (stored == null) return null;
    return codec.decode(stored);
  }

  /// Decodes the entire payload as a typed DTO with a JSON decoder.
  T? payloadJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    final stored = payload;
    if (stored == null) return null;
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(stored);
  }

  /// Decodes the entire payload as a typed DTO with a version-aware JSON
  /// decoder.
  T? payloadVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    final stored = payload;
    if (stored == null) return null;
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(stored);
  }

  /// Returns the decoded payload value, or [fallback] when it is absent.
  T payloadValueOr<T>(T fallback, {PayloadCodec<T>? codec}) {
    return payloadValue<T>(codec: codec) ?? fallback;
  }

  /// Returns the decoded payload value, throwing when it is absent.
  T requiredPayloadValue<T>({PayloadCodec<T>? codec}) {
    if (payload == null) {
      throw StateError("Task '$id' does not have a payload.");
    }
    return payloadValue<T>(codec: codec) as T;
  }

  /// The error that occurred during task execution, if any.
  final TaskError? error;

  /// Additional metadata for this task status.
  final Map<String, Object?> meta;

  /// Decodes the full task metadata payload with [codec].
  T metaAs<T>({required PayloadCodec<T> codec}) {
    return codec.decode(meta);
  }

  /// Decodes the full task metadata payload with a JSON decoder.
  T metaJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(meta);
  }

  /// Decodes the full task metadata payload with a version-aware JSON decoder.
  T metaVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(meta);
  }

  /// The attempt number for this task execution.
  final int attempt;

  /// Task name extracted from metadata (`task` / `stem.task`).
  String? get taskName =>
      meta['task']?.toString() ?? meta['stem.task']?.toString();

  /// Queue name extracted from metadata (`queue` / `stem.queue`).
  String? get queueName =>
      meta['queue']?.toString() ?? meta['stem.queue']?.toString();

  /// Namespace extracted from metadata (`namespace` / `stem.namespace`).
  String? get namespace =>
      meta['namespace']?.toString() ?? meta['stem.namespace']?.toString();

  /// Worker id that reported this status, if available.
  String? get workerId => meta['worker']?.toString();

  /// Workflow name associated with this task status, if any.
  String? get workflowName => _taskStatusString(
    meta,
    const ['stem.workflow.name', 'workflow.name', 'workflow'],
  );

  /// Workflow run identifier associated with this task status, if any.
  String? get workflowRunId => _taskStatusString(
    meta,
    const ['stem.workflow.runId', 'workflow.runId'],
  );

  /// Stable workflow definition identifier, if provided.
  String? get workflowId => _taskStatusString(
    meta,
    const ['stem.workflow.id', 'workflow.id'],
  );

  /// Workflow step name associated with this task status, if any.
  String? get workflowStep => _taskStatusString(
    meta,
    const ['stem.workflow.step', 'workflow.step', 'step'],
  );

  /// Workflow step index associated with this task status, if any.
  int? get workflowStepIndex => _taskStatusInt(
    meta,
    const ['stem.workflow.stepIndex', 'workflow.stepIndex'],
  );

  /// Workflow iteration associated with this task status, if any.
  int? get workflowIteration => _taskStatusInt(
    meta,
    const ['stem.workflow.iteration', 'workflow.iteration'],
  );

  /// Workflow channel (`orchestration` or `execution`) for this status.
  String? get workflowChannel => _taskStatusString(
    meta,
    const ['stem.workflow.channel', 'workflow.channel'],
  );

  /// Whether this status represents a continuation orchestration dispatch.
  bool get workflowContinuation =>
      meta['stem.workflow.continuation'] == true ||
      meta['workflow.continuation'] == true;

  /// Continuation reason label when present.
  String? get workflowContinuationReason => _taskStatusString(
    meta,
    const [
      'stem.workflow.continuationReason',
      'workflow.continuationReason',
    ],
  );

  /// Orchestration queue associated with the workflow runtime.
  String? get workflowOrchestrationQueue => _taskStatusString(
    meta,
    const ['stem.workflow.orchestrationQueue', 'workflow.orchestrationQueue'],
  );

  /// Continuation queue associated with the workflow runtime.
  String? get workflowContinuationQueue => _taskStatusString(
    meta,
    const ['stem.workflow.continuationQueue', 'workflow.continuationQueue'],
  );

  /// Execution queue associated with the workflow runtime.
  String? get workflowExecutionQueue => _taskStatusString(
    meta,
    const ['stem.workflow.executionQueue', 'workflow.executionQueue'],
  );

  /// Serialization format used by the workflow run context.
  String? get workflowSerializationFormat => _taskStatusString(
    meta,
    const ['stem.workflow.serialization.format', 'workflow.serialization'],
  );

  /// Serialization version used by the workflow run context.
  String? get workflowSerializationVersion => _taskStatusString(
    meta,
    const [
      'stem.workflow.serialization.version',
      'workflow.serialization.version',
    ],
  );

  /// Per-run stream identifier used for framing metadata.
  String? get workflowStreamId => _taskStatusString(
    meta,
    const ['stem.workflow.stream.id', 'workflow.stream.id'],
  );

  /// Processing start timestamp recorded by the worker, if present.
  DateTime? get startedAt => _taskStatusDate(meta['startedAt']);

  /// Completion timestamp recorded by the worker, if present.
  DateTime? get completedAt => _taskStatusDate(meta['completedAt']);

  /// Failure timestamp recorded by the worker, if present.
  DateTime? get failedAt => _taskStatusDate(meta['failedAt']);

  /// Revocation timestamp when this task was revoked, if present.
  DateTime? get revokedAt => _taskStatusDate(meta['revokedAt']);

  /// Revocation reason, when recorded.
  String? get revokedReason => meta['revokedReason']?.toString();

  /// Actor that requested revocation, when recorded.
  String? get revokedBy => meta['revokedBy']?.toString();

  /// Whether this status indicates a revoked task.
  bool get wasRevoked => meta['revoked'] == true || revokedAt != null;

  /// Whether this status indicates a time-limit expiration.
  bool get isExpired => meta['stem.expired'] == true || meta['expired'] == true;

  /// Hard execution time limit reported by worker metadata, if present.
  Duration? get hardTimeLimit => _taskStatusDuration(meta['stem.timeLimitMs']);

  /// Soft execution time limit reported by worker metadata, if present.
  Duration? get softTimeLimit =>
      _taskStatusDuration(meta['stem.softTimeLimitMs']);

  /// Parent task id in a lineage chain, if present.
  String? get parentTaskId => meta['stem.parentTaskId']?.toString();

  /// Root task id in a lineage chain, if present.
  String? get rootTaskId => meta['stem.rootTaskId']?.toString();

  /// Serializes this status to JSON.
  Map<String, Object?> toJson() => {
    'id': id,
    'state': state.name,
    'payload': payload,
    'error': error?.toJson(),
    'meta': meta,
    'attempt': attempt,
  };
}

DateTime? _taskStatusDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

String? _taskStatusString(Map<String, Object?> meta, List<String> keys) {
  for (final key in keys) {
    final value = meta[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

int? _taskStatusInt(Map<String, Object?> meta, List<String> keys) {
  for (final key in keys) {
    final value = meta[key];
    if (value == null) continue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value.toString());
    if (parsed != null) return parsed;
  }
  return null;
}

Duration? _taskStatusDuration(Object? value) {
  if (value is num) {
    return Duration(milliseconds: value.toInt());
  }
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed == null) return null;
  return Duration(milliseconds: parsed);
}

/// Immutable record representing a persisted task status with timestamps.
class TaskStatusRecord {
  /// Creates a task status record.
  const TaskStatusRecord({
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Task status payload.
  final TaskStatus status;

  /// Timestamp when the task status was first persisted.
  final DateTime createdAt;

  /// Timestamp when the task status was last updated.
  final DateTime updatedAt;
}

/// Query parameters used to list task status records.
class TaskStatusListRequest {
  /// Creates a task status list request.
  const TaskStatusListRequest({
    this.state,
    this.queue,
    this.meta = const {},
    this.limit = 50,
    this.offset = 0,
  }) : assert(limit >= 0, 'limit must be >= 0'),
       assert(offset >= 0, 'offset must be >= 0');

  /// Optional task state filter.
  final TaskState? state;

  /// Optional queue filter (matches `meta["queue"]`).
  final String? queue;

  /// Metadata key/value filters (null values match key presence).
  final Map<String, Object?> meta;

  /// Maximum number of records to return.
  final int limit;

  /// Number of records to skip.
  final int offset;
}

/// Paginated page of task status records.
class TaskStatusPage {
  /// Creates a task status page.
  const TaskStatusPage({required this.items, this.nextOffset});

  /// Records included in this page.
  final List<TaskStatusRecord> items;

  /// Offset to continue pagination, or `null` if no more results.
  final int? nextOffset;

  /// Whether additional records are available.
  bool get hasMore => nextOffset != null;
}

/// Error metadata captured for failures.
class TaskError {
  /// Creates an error metadata record.
  const TaskError({
    required this.type,
    required this.message,
    this.stack,
    this.retryable = false,
    this.meta = const {},
  });

  /// Builds error metadata from persisted JSON.
  factory TaskError.fromJson(Map<String, Object?> json) {
    return TaskError(
      type: json['type'] as String? ?? 'Unknown',
      message: json['message'] as String? ?? '',
      stack: json['stack'] as String?,
      retryable: json['retryable'] as bool? ?? false,
      meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  /// The type of the error.
  final String type;

  /// The error message.
  final String message;

  /// The stack trace of the error, if available.
  final String? stack;

  /// Whether this error is retryable.
  final bool retryable;

  /// Additional metadata for this error.
  final Map<String, Object?> meta;

  /// Decodes the full error metadata payload as a typed DTO with [codec].
  T metaAs<T>({required PayloadCodec<T> codec}) {
    return codec.decode(meta);
  }

  /// Decodes the full error metadata payload as a typed DTO with a JSON
  /// decoder.
  T metaJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(meta);
  }

  /// Decodes the full error metadata payload as a typed DTO with a
  /// version-aware JSON decoder.
  T metaVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(meta);
  }

  /// Serializes the error metadata to JSON.
  Map<String, Object?> toJson() => {
    'type': type,
    'message': message,
    'stack': stack,
    'retryable': retryable,
    'meta': meta,
  };
}

/// Signals an explicit retry request from within a task handler.
class TaskRetryRequest implements Exception {
  /// Creates a retry request with optional scheduling overrides.
  TaskRetryRequest({
    this.countdown,
    this.eta,
    this.retryPolicy,
    this.maxRetries,
    this.timeLimit,
    this.softTimeLimit,
  });

  /// Relative delay before retrying.
  final Duration? countdown;

  /// Absolute timestamp for retry.
  final DateTime? eta;

  /// Optional retry policy override.
  final TaskRetryPolicy? retryPolicy;

  /// Optional max retries override.
  final int? maxRetries;

  /// Optional hard time limit override.
  final Duration? timeLimit;

  /// Optional soft time limit override.
  final Duration? softTimeLimit;
}

/// Dead letter queue entry containing the failed [envelope] and metadata.
class DeadLetterEntry {
  /// Creates a dead letter entry record.
  DeadLetterEntry({
    required this.envelope,
    required this.deadAt,
    this.reason,
    Map<String, Object?>? meta,
  }) : meta = Map.unmodifiable(meta ?? const {});

  /// Builds a dead letter entry from persisted JSON.
  factory DeadLetterEntry.fromJson(Map<String, Object?> json) {
    return DeadLetterEntry(
      envelope: Envelope.fromJson(
        (json['envelope']! as Map).cast<String, Object?>(),
      ),
      reason: json['reason'] as String?,
      meta: (json['meta'] as Map?)?.cast<String, Object?>(),
      deadAt: DateTime.parse(json['deadAt']! as String),
    );
  }

  /// Envelope that failed processing.
  final Envelope envelope;

  /// Optional reason describing the failure.
  final String? reason;

  /// Additional metadata captured at failure time.
  final Map<String, Object?> meta;

  /// Decodes the full metadata payload as a typed DTO with [codec].
  T metaAs<T>({required PayloadCodec<T> codec}) {
    return codec.decode(meta);
  }

  /// Decodes the full metadata payload as a typed DTO with a JSON decoder.
  T metaJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(meta);
  }

  /// Decodes the full metadata payload as a typed DTO with a version-aware
  /// JSON decoder.
  T metaVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(meta);
  }

  /// Timestamp when the task was dead-lettered.
  final DateTime deadAt;

  /// Serializes this entry to JSON.
  Map<String, Object?> toJson() => {
    'envelope': envelope.toJson(),
    'reason': reason,
    'meta': meta,
    'deadAt': deadAt.toIso8601String(),
  };
}

/// Page of dead letter results with optional continuation offset.
class DeadLetterPage {
  /// Creates a page of dead letter entries.
  const DeadLetterPage({required this.entries, this.nextOffset});

  /// Entries included in this page.
  final List<DeadLetterEntry> entries;

  /// Next offset to continue pagination, or `null` if no more entries.
  final int? nextOffset;

  /// Whether additional entries are available.
  bool get hasMore => nextOffset != null;
}

/// Result describing entries considered for replay.
class DeadLetterReplayResult {
  /// Creates a replay result wrapper.
  const DeadLetterReplayResult({required this.entries, required this.dryRun});

  /// Entries that matched the replay filters.
  final List<DeadLetterEntry> entries;

  /// Whether this invocation was a dry run (no mutations performed).
  final bool dryRun;

  /// Number of entries touched.
  int get count => entries.length;
}

/// Portable task-status persistence capability.
abstract interface class TaskStatusStore {
  /// Persists the latest task state.
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt,
    Map<String, Object?> meta,
    Duration? ttl,
  });

  /// Retrieves the latest status for [taskId].
  Future<TaskStatus?> get(String taskId);

  /// Watches status changes for [taskId].
  Stream<TaskStatus> watch(String taskId);

  /// Lists task status records matching [request].
  Future<TaskStatusPage> listTaskStatuses(TaskStatusListRequest request);

  /// Updates the expiration for [taskId].
  Future<void> expire(String taskId, Duration ttl);
}

/// Persistence capability for worker heartbeat state.
abstract interface class WorkerHeartbeatStore {
  /// Persists a worker heartbeat snapshot.
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat);

  /// Retrieves a heartbeat by worker id.
  Future<WorkerHeartbeat?> getWorkerHeartbeat(String workerId);

  /// Lists the latest worker heartbeat snapshots.
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats();
}

/// Persistence capability for task groups and chord arbitration.
abstract interface class GroupResultStore {
  /// Initializes a task group.
  Future<void> initGroup(GroupDescriptor descriptor);

  /// Adds a task result to a group.
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status);

  /// Retrieves a task group.
  Future<GroupStatus?> getGroup(String groupId);

  /// Atomically claims responsibility for dispatching a chord callback.
  Future<bool> claimChord(
    String groupId, {
    String? callbackTaskId,
    DateTime? dispatchedAt,
  });
}

/// Result backend compatibility facade combining optional store capabilities.
/// Since: 0.1.0
abstract class ResultBackend
    implements TaskStatusStore, WorkerHeartbeatStore, GroupResultStore {
  /// Sets the status for the task with the given [taskId].
  ///
  /// Updates the [state], [payload], [error], [attempt], and [meta], and sets a
  /// [ttl] if provided.
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt,
    Map<String, Object?> meta,
    Duration? ttl,
  });

  /// Retrieves the [TaskStatus] for the task with the given [taskId], or null
  /// if not found.
  Future<TaskStatus?> get(String taskId);

  /// Returns a stream of [TaskStatus] updates for the task with the given
  /// [taskId].
  Stream<TaskStatus> watch(String taskId);

  /// Lists task status records using the provided [request] filters.
  ///
  /// Implementations SHOULD order results from newest to oldest.
  Future<TaskStatusPage> listTaskStatuses(TaskStatusListRequest request) async {
    return const TaskStatusPage(items: []);
  }

  /// Persist the latest [heartbeat] snapshot for a worker.
  Future<void> setWorkerHeartbeat(WorkerHeartbeat heartbeat);

  /// Retrieves the last persisted heartbeat snapshot for [workerId], or null if
  /// no heartbeat has been recorded within the retention window.
  Future<WorkerHeartbeat?> getWorkerHeartbeat(String workerId);

  /// Lists all worker heartbeat snapshots.
  Future<List<WorkerHeartbeat>> listWorkerHeartbeats();

  /// Initializes a group with the given [descriptor].
  Future<void> initGroup(GroupDescriptor descriptor);

  /// Adds the [status] to the group with the given [groupId] and returns the
  /// updated [GroupStatus].
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status);

  /// Retrieves the [GroupStatus] for the group with the given [groupId], or
  /// null if not found.
  Future<GroupStatus?> getGroup(String groupId);

  /// Updates the expiration for the given [taskId].
  Future<void> expire(String taskId, Duration ttl);

  /// Attempts to claim responsibility for dispatching the chord callback for
  /// [groupId]. Returns `true` only for the first caller; subsequent callers
  /// receive `false` once the chord has been claimed. When [callbackTaskId] or
  /// [dispatchedAt] are provided, implementations SHOULD persist them with the
  /// group metadata so other components can observe dispatch progress.
  Future<bool> claimChord(
    String groupId, {
    String? callbackTaskId,
    DateTime? dispatchedAt,
  });

  /// Releases any resources held by the backend.
  Future<void> close() async {}
}

/// Optional atomic terminal-state arbitration for result backends.
///
/// Workers can receive the same delivery more than once across processes. A
/// backend implementing this capability must persist a [TaskStatus] only when
/// the current record is absent or non-terminal, and must do that check and
/// write atomically. It returns `true` for the writer that won the terminal
/// state and `false` when another terminal state was already persisted.
///
/// Implementations should normally be used after the producer has created the
/// task's initial queued record. A backend may return `false` when a task
/// record is absent if its storage cannot atomically create-and-arbitrate a
/// missing row.
///
/// This is deliberately separate from [ResultBackend] so existing custom
/// backends remain source compatible. Workers fall back to [ResultBackend.set]
/// for backends that do not advertise this capability; that fallback is not a
/// cross-process first-writer-wins guarantee.
abstract interface class AtomicTerminalResultStore {
  /// Whether this backend provides a cross-process atomic terminal write.
  bool get supportsAtomicTerminalWrites;

  /// Attempts to persist [status] as the task's terminal state.
  Future<bool> setTerminalIfAbsent(
    TaskStatus status, {
    Duration? ttl,
  });
}

/// Compatibility name for existing result backend implementations.
abstract interface class AtomicTerminalResultBackend
    implements AtomicTerminalResultStore {}

/// Schedule entry persisted by a Beat-like scheduler.
class ScheduleEntry {
  /// Creates a schedule entry for a recurring task.
  ScheduleEntry({
    required this.id,
    required this.taskName,
    required this.queue,
    required this.spec,
    Map<String, Object?>? args,
    Map<String, Object?>? kwargs,
    this.enabled = true,
    this.jitter,
    this.lastRunAt,
    this.nextRunAt,
    this.lastJitter,
    this.lastError,
    this.timezone,
    this.totalRunCount = 0,
    this.lastSuccessAt,
    this.lastErrorAt,
    this.drift,
    this.expireAt,
    this.createdAt,
    this.updatedAt,
    this.version = 0,
    Map<String, Object?>? meta,
  }) : args = Map.unmodifiable(args ?? const {}),
       kwargs = Map.unmodifiable(kwargs ?? const {}),
       meta = Map.unmodifiable(meta ?? const {});

  /// Builds a schedule entry from persisted JSON.
  factory ScheduleEntry.fromJson(Map<String, Object?> json) {
    final spec = ScheduleSpec.fromPersisted(json['spec']);
    return ScheduleEntry(
      id: json['id']! as String,
      taskName: json['taskName']! as String,
      queue: json['queue']! as String,
      spec: spec,
      args: (json['args'] as Map?)?.cast<String, Object?>(),
      kwargs: (json['kwargs'] as Map?)?.cast<String, Object?>(),
      enabled: json['enabled'] as bool? ?? true,
      jitter: json['jitterMs'] != null
          ? Duration(milliseconds: (json['jitterMs']! as num).toInt())
          : null,
      lastRunAt: _parseOptionalDate(json['lastRunAt']),
      nextRunAt: _parseOptionalDate(json['nextRunAt']),
      lastJitter: json['lastJitterMs'] != null
          ? Duration(milliseconds: (json['lastJitterMs']! as num).toInt())
          : null,
      lastError: json['lastError'] as String?,
      timezone: json['timezone'] as String?,
      totalRunCount: (json['totalRunCount'] as num?)?.toInt() ?? 0,
      lastSuccessAt: _parseOptionalDate(json['lastSuccessAt']),
      lastErrorAt: _parseOptionalDate(json['lastErrorAt']),
      drift: json['driftMs'] != null
          ? Duration(milliseconds: (json['driftMs']! as num).toInt())
          : null,
      expireAt: _parseOptionalDate(json['expireAt']),
      createdAt: _parseOptionalDate(json['createdAt']),
      updatedAt: _parseOptionalDate(json['updatedAt']),
      version: (json['version'] as num?)?.toInt() ?? 0,
      meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  /// The unique identifier for this schedule entry.
  final String id;

  /// The name of the task to be scheduled.
  final String taskName;

  /// The queue to which the task should be sent.
  final String queue;

  /// The schedule specification.
  final ScheduleSpec spec;

  /// Positional arguments to pass to the task.
  final Map<String, Object?> args;

  /// Decodes the full args payload as a typed DTO with [codec].
  T argsAs<T>({required PayloadCodec<T> codec}) {
    return codec.decode(args);
  }

  /// Decodes the full args payload as a typed DTO with a JSON decoder.
  T argsJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(args);
  }

  /// Decodes the full args payload as a typed DTO with a version-aware JSON
  /// decoder.
  T argsVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(args);
  }

  /// Keyword-style arguments passed to the task.
  final Map<String, Object?> kwargs;

  /// Decodes the full kwargs payload as a typed DTO with [codec].
  T kwargsAs<T>({required PayloadCodec<T> codec}) {
    return codec.decode(kwargs);
  }

  /// Decodes the full kwargs payload as a typed DTO with a JSON decoder.
  T kwargsJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(kwargs);
  }

  /// Decodes the full kwargs payload as a typed DTO with a version-aware JSON
  /// decoder.
  T kwargsVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(kwargs);
  }

  /// Whether this schedule entry is enabled.
  final bool enabled;

  /// Optional jitter to add randomness to the schedule.
  final Duration? jitter;

  /// The timestamp of the last run, if any.
  final DateTime? lastRunAt;

  /// The next scheduled run timestamp, if known.
  final DateTime? nextRunAt;

  /// The jitter applied during the most recent execution.
  final Duration? lastJitter;

  /// The last error recorded for this schedule, if any.
  final String? lastError;

  /// Optional timezone identifier (IANA) for cron evaluation.
  final String? timezone;

  /// Total successful or attempted run count.
  final int totalRunCount;

  /// Timestamp of the most recent successful run.
  final DateTime? lastSuccessAt;

  /// Timestamp of the most recent errored run.
  final DateTime? lastErrorAt;

  /// Drift observed during the last execution (actual - scheduled).
  final Duration? drift;

  /// Optional expiry: disable the entry after this time.
  final DateTime? expireAt;

  /// Creation timestamp persisted by the store, if provided.
  final DateTime? createdAt;

  /// Last update timestamp persisted by the store, if provided.
  final DateTime? updatedAt;

  /// Additional metadata for this schedule entry.
  final Map<String, Object?> meta;

  /// Decodes the full metadata payload as a typed DTO with [codec].
  T metaAs<T>({required PayloadCodec<T> codec}) {
    return codec.decode(meta);
  }

  /// Decodes the full metadata payload as a typed DTO with a JSON decoder.
  T metaJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return PayloadCodec<T>.json(
      decode: decode,
      typeName: typeName,
    ).decode(meta);
  }

  /// Decodes the full metadata payload as a typed DTO with a version-aware
  /// JSON decoder.
  T metaVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: version,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    ).decode(meta);
  }

  /// Optimistic locking version assigned by the underlying store.
  final int version;

  /// Sentinel value used to distinguish "unset" from explicit null overrides.
  static const Object _sentinel = Object();

  /// Returns a copy of this entry with the provided overrides.
  ScheduleEntry copyWith({
    String? id,
    String? taskName,
    String? queue,
    ScheduleSpec? spec,
    Map<String, Object?>? args,
    Map<String, Object?>? kwargs,
    bool? enabled,
    Duration? jitter,
    DateTime? lastRunAt,
    Object? nextRunAt = _sentinel,
    Object? lastJitter = _sentinel,
    Object? lastError = _sentinel,
    Object? timezone = _sentinel,
    int? totalRunCount,
    Object? lastSuccessAt = _sentinel,
    Object? lastErrorAt = _sentinel,
    Object? drift = _sentinel,
    Object? expireAt = _sentinel,
    Object? createdAt = _sentinel,
    Object? updatedAt = _sentinel,
    int? version,
    Map<String, Object?>? meta,
  }) {
    return ScheduleEntry(
      id: id ?? this.id,
      taskName: taskName ?? this.taskName,
      queue: queue ?? this.queue,
      spec: spec ?? this.spec,
      args: args ?? this.args,
      kwargs: kwargs ?? this.kwargs,
      enabled: enabled ?? this.enabled,
      jitter: jitter ?? this.jitter,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt == _sentinel
          ? this.nextRunAt
          : nextRunAt as DateTime?,
      lastJitter: lastJitter == _sentinel
          ? this.lastJitter
          : lastJitter as Duration?,
      lastError: lastError == _sentinel ? this.lastError : lastError as String?,
      timezone: timezone == _sentinel ? this.timezone : timezone as String?,
      totalRunCount: totalRunCount ?? this.totalRunCount,
      lastSuccessAt: lastSuccessAt == _sentinel
          ? this.lastSuccessAt
          : lastSuccessAt as DateTime?,
      lastErrorAt: lastErrorAt == _sentinel
          ? this.lastErrorAt
          : lastErrorAt as DateTime?,
      drift: drift == _sentinel ? this.drift : drift as Duration?,
      expireAt: expireAt == _sentinel ? this.expireAt : expireAt as DateTime?,
      createdAt: createdAt == _sentinel
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: updatedAt == _sentinel
          ? this.updatedAt
          : updatedAt as DateTime?,
      version: version ?? this.version,
      meta: meta ?? this.meta,
    );
  }

  /// Serializes this entry to JSON.
  Map<String, Object?> toJson() => {
    'id': id,
    'taskName': taskName,
    'queue': queue,
    'spec': spec.toJson(),
    'args': args,
    if (kwargs.isNotEmpty) 'kwargs': kwargs,
    'enabled': enabled,
    'jitterMs': jitter?.inMilliseconds,
    'lastRunAt': lastRunAt?.toIso8601String(),
    'nextRunAt': nextRunAt?.toIso8601String(),
    'lastJitterMs': lastJitter?.inMilliseconds,
    'lastError': lastError,
    'timezone': timezone,
    'totalRunCount': totalRunCount,
    'lastSuccessAt': lastSuccessAt?.toIso8601String(),
    'lastErrorAt': lastErrorAt?.toIso8601String(),
    'driftMs': drift?.inMilliseconds,
    'expireAt': expireAt?.toIso8601String(),
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    'version': version,
    'meta': meta,
  };
}

DateTime? _parseOptionalDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.parse(value);
  }
  return null;
}

/// Storage abstraction used by the scheduler to fetch due entries.
/// Since: 0.1.0
abstract class ScheduleStore {
  /// Returns a list of [ScheduleEntry] instances due at [now], limited to
  /// [limit].
  Future<List<ScheduleEntry>> due(DateTime now, {int limit = 100});

  /// Inserts or updates the [entry] in the store.
  Future<void> upsert(ScheduleEntry entry);

  /// Removes the schedule entry with the given [id] from the store.
  Future<void> remove(String id);

  /// Returns all schedule entries.
  Future<List<ScheduleEntry>> list({int? limit});

  /// Retrieves the schedule entry with [id], or null if absent.
  Future<ScheduleEntry?> get(String id);

  /// Updates execution metadata for the entry [id].
  Future<void> markExecuted(
    String id, {
    required DateTime scheduledFor,
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
    bool success = true,
    Duration? runDuration,
    DateTime? nextRunAt,
    Duration? drift,
  });
}

/// Thrown when a schedule mutation conflicts with a newer store version.
class ScheduleConflictException implements Exception {
  /// Creates a conflict error for the given entry [id].
  ScheduleConflictException(
    this.id, {
    required this.expectedVersion,
    required this.actualVersion,
  });

  /// Identifier of the conflicted schedule entry.
  final String id;

  /// Version the caller attempted to update.
  final int expectedVersion;

  /// Version currently persisted in the store.
  final int actualVersion;

  @override
  String toString() =>
      'ScheduleConflictException(id: $id, expected: $expectedVersion, '
      'actual: $actualVersion)';
}

/// Configuration options attached to task handlers.
class TaskOptions {
  /// Creates task options used during enqueue and execution.
  const TaskOptions({
    this.queue = 'default',
    this.maxRetries = 0,
    this.softTimeLimit,
    this.hardTimeLimit,
    this.rateLimit,
    this.groupRateLimit,
    this.groupRateKey,
    this.groupRateKeyHeader = 'tenant',
    this.groupRateLimiterFailureMode = RateLimiterFailureMode.failOpen,
    this.unique = false,
    this.uniqueFor,
    this.priority = 0,
    this.acksLate = true,
    this.visibilityTimeout,
    this.retryPolicy,
  });

  /// Builds options from JSON-friendly data.
  factory TaskOptions.fromJson(Map<String, Object?> json) {
    TaskRetryPolicy? retryPolicy;
    final retryValue = json['retryPolicy'];
    if (retryValue is TaskRetryPolicy) {
      retryPolicy = retryValue;
    } else if (retryValue is Map) {
      retryPolicy = TaskRetryPolicy.fromJson(
        retryValue.cast<String, Object?>(),
      );
    }
    final failureMode =
        _parseFailureMode(
          json['groupRateLimiterFailureMode'],
        ) ??
        RateLimiterFailureMode.failOpen;
    return TaskOptions(
      queue: json['queue'] as String? ?? 'default',
      maxRetries: (json['maxRetries'] as num?)?.toInt() ?? 0,
      softTimeLimit: _durationFromJson(json['softTimeLimitMs']),
      hardTimeLimit: _durationFromJson(json['hardTimeLimitMs']),
      rateLimit: RateLimit.parse(json['rateLimit']),
      groupRateLimit: RateLimit.parse(json['groupRateLimit']),
      groupRateKey: json['groupRateKey'] as String?,
      groupRateKeyHeader: json['groupRateKeyHeader'] as String? ?? 'tenant',
      groupRateLimiterFailureMode: failureMode,
      unique: json['unique'] as bool? ?? false,
      uniqueFor: _durationFromJson(json['uniqueForMs']),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      acksLate: json['acksLate'] as bool? ?? true,
      visibilityTimeout: _durationFromJson(json['visibilityTimeoutMs']),
      retryPolicy: retryPolicy,
    );
  }

  /// The queue to which tasks with these options should be sent.
  final String queue;

  /// The maximum number of retries for tasks with these options.
  final int maxRetries;

  /// The soft time limit for task execution.
  final Duration? softTimeLimit;

  /// The hard time limit for task execution.
  final Duration? hardTimeLimit;

  /// The rate limit for tasks with these options.
  final RateLimit? rateLimit;

  /// Group-scoped rate limit shared by tasks that resolve to
  /// the same group key.
  final RateLimit? groupRateLimit;

  /// Optional static group key used for group-scoped rate limiting.
  final String? groupRateKey;

  /// Header key used to resolve group identity when [groupRateKey] is not set.
  final String groupRateKeyHeader;

  /// Behavior to apply when group limiter calls fail.
  final RateLimiterFailureMode groupRateLimiterFailureMode;

  /// Whether tasks with these options should be unique.
  final bool unique;

  /// The duration for which tasks should remain unique.
  final Duration? uniqueFor;

  /// The priority of tasks with these options.
  final int priority;

  /// Whether acknowledgments should be sent late.
  final bool acksLate;

  /// The visibility timeout for tasks.
  final Duration? visibilityTimeout;

  /// Optional per-task retry policy overrides.
  final TaskRetryPolicy? retryPolicy;

  /// Creates a modified copy of these options.
  TaskOptions copyWith({
    String? queue,
    int? maxRetries,
    Duration? softTimeLimit,
    Duration? hardTimeLimit,
    RateLimit? rateLimit,
    RateLimit? groupRateLimit,
    String? groupRateKey,
    String? groupRateKeyHeader,
    RateLimiterFailureMode? groupRateLimiterFailureMode,
    bool? unique,
    Duration? uniqueFor,
    int? priority,
    bool? acksLate,
    Duration? visibilityTimeout,
    TaskRetryPolicy? retryPolicy,
  }) {
    return TaskOptions(
      queue: queue ?? this.queue,
      maxRetries: maxRetries ?? this.maxRetries,
      softTimeLimit: softTimeLimit ?? this.softTimeLimit,
      hardTimeLimit: hardTimeLimit ?? this.hardTimeLimit,
      rateLimit: rateLimit ?? this.rateLimit,
      groupRateLimit: groupRateLimit ?? this.groupRateLimit,
      groupRateKey: groupRateKey ?? this.groupRateKey,
      groupRateKeyHeader: groupRateKeyHeader ?? this.groupRateKeyHeader,
      groupRateLimiterFailureMode:
          groupRateLimiterFailureMode ?? this.groupRateLimiterFailureMode,
      unique: unique ?? this.unique,
      uniqueFor: uniqueFor ?? this.uniqueFor,
      priority: priority ?? this.priority,
      acksLate: acksLate ?? this.a…4467 tokens truncated….decode(args);
  }

  /// Decodes the full task-argument payload as a version-aware DTO.
  T argsVersionedJson<T>({
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return PayloadCodec<T>.versionedJson(
      version: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion ?? defaultVersion,
      typeName: typeName,
    ).decode(args);
  }

  /// Returns the decoded task arg for [key], or `null`.
  T? arg<T>(String key, {PayloadCodec<T>? codec}) {
    return args.value<T>(key, codec: codec);
  }

  /// Returns the decoded task arg for [key], or [fallback].
  T argOr<T>(String key, T fallback, {PayloadCodec<T>? codec}) {
    return args.valueOr<T>(key, fallback, codec: codec);
  }

  /// Returns the decoded task arg for [key], throwing when absent.
  T requiredArg<T>(String key, {PayloadCodec<T>? codec}) {
    return args.requiredValue<T>(key, codec: codec);
  }

  /// Returns the decoded task arg DTO for [key], or `null`.
  T? argJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return args.valueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded task arg DTO for [key], or [fallback].
  T argJsonOr<T>(
    String key,
    T fallback, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return args.valueJsonOr<T>(
      key,
      fallback,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded task arg DTO for [key], throwing when absent.
  T requiredArgJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return args.requiredValueJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded version-aware task arg DTO for [key], or `null`.
  T? argVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return args.valueVersionedJson<T>(
      key,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    );
  }

  /// Returns the decoded version-aware task arg DTO for [key], or [fallback].
  T argVersionedJsonOr<T>(
    String key,
    T fallback, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return args.valueVersionedJsonOr<T>(
      key,
      fallback,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    );
  }

  /// Returns the decoded version-aware task arg DTO for [key], throwing when
  /// absent.
  T requiredArgVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return args.requiredValueVersionedJson<T>(
      key,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    );
  }

  /// Returns the decoded task arg DTO list for [key], or `null`.
  List<T>? argListJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return args.valueListJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded task arg DTO list for [key], or [fallback].
  List<T> argListJsonOr<T>(
    String key,
    List<T> fallback, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return args.valueListJsonOr<T>(
      key,
      fallback,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded task arg DTO list for [key], throwing when absent.
  List<T> requiredArgListJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return args.requiredValueListJson<T>(
      key,
      decode: decode,
      typeName: typeName,
    );
  }

  /// Returns the decoded version-aware task arg DTO list for [key], or `null`.
  List<T>? argListVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return args.valueListVersionedJson<T>(
      key,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    );
  }

  /// Returns the decoded version-aware task arg DTO list for [key], or
  /// [fallback].
  List<T> argListVersionedJsonOr<T>(
    String key,
    List<T> fallback, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return args.valueListVersionedJsonOr<T>(
      key,
      fallback,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    );
  }

  /// Returns the decoded version-aware task arg DTO list for [key], throwing
  /// when absent.
  List<T> requiredArgListVersionedJson<T>(
    String key, {
    required T Function(Map<String, dynamic> payload, int version) decode,
    int defaultVersion = 1,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return args.requiredValueListVersionedJson<T>(
      key,
      defaultVersion: defaultVersion,
      decode: decode,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: typeName,
    );
  }
}

/// Shared execution surface for task handlers and isolate entrypoints.
abstract interface class TaskExecutionContext
    implements
        TaskEnqueuer,
        WorkflowCaller,
        WorkflowEventEmitter,
        TaskInputContext {
  /// The unique identifier of the task.
  String get id;

  /// The current attempt number.
  int get attempt;

  /// Headers associated with the task.
  Map<String, String> get headers;

  /// Metadata for the task invocation.
  Map<String, Object?> get meta;

  /// Cooperative cancellation state for this invocation.
  TaskCancellationToken get cancellation;

  /// Notify the worker that the task is still running.
  void heartbeat();

  /// Request an extension of the current lease by [by].
  Future<void> extendLease(Duration by);

  /// Report progress back to the worker.
  Future<void> progress(double percentComplete, {Map<String, Object?>? data});

  /// Request a retry of the current task.
  Future<void> retry({
    Duration? countdown,
    DateTime? eta,
    TaskRetryPolicy? retryPolicy,
    int? maxRetries,
    Duration? timeLimit,
    Duration? softTimeLimit,
  });

  /// Alias for [enqueue] when spawning follow-up work from the current task.
  Future<String> spawn(
    String name, {
    Map<String, Object?> args,
    Map<String, String> headers,
    TaskOptions options,
    DateTime? notBefore,
    Map<String, Object?> meta,
    TaskEnqueueOptions? enqueueOptions,
  });
}

/// Cooperative cancellation state exposed to task code.
///
/// Cancellation is advisory for inline handlers: task code must call
/// [throwIfCancelled] at safe points. Isolate-backed handlers can still be
/// terminated by the worker's hard timeout or hard shutdown path.
class TaskCancellationToken {
  /// Creates a token whose state is optionally resolved by [isCancelled].
  TaskCancellationToken({bool Function()? isCancelled})
    : _isCancelled = isCancelled,
      _state = _CancellationState();

  /// Creates a token that is never cancelled.
  const TaskCancellationToken.none() : _isCancelled = null, _state = null;

  final bool Function()? _isCancelled;
  final _CancellationState? _state;

  /// Whether cancellation has been requested.
  bool get isCancellationRequested =>
      (_state?.cancelled ?? false) || (_isCancelled?.call() ?? false);

  /// Marks this token as cancelled.
  void cancel() {
    final state = _state;
    if (state != null) state.cancelled = true;
  }

  /// Throws when cancellation has been requested.
  void throwIfCancelled() {
    if (isCancellationRequested) {
      throw const TaskCancellationException();
    }
  }
}

class _CancellationState {
  bool cancelled = false;
}

/// Thrown when a task cooperatively observes cancellation.
class TaskCancellationException implements Exception {
  /// Creates a cancellation exception.
  const TaskCancellationException();

  @override
  String toString() => 'Task execution was cancelled';
}

/// Shared task-progress helpers for execution contexts.
extension TaskExecutionContextProgressX on TaskExecutionContext {
  /// Report progress with a JSON-serializable DTO payload.
  Future<void> progressJson<T>(
    double percentComplete,
    T value, {
    String? typeName,
  }) {
    return progress(
      percentComplete,
      data: Map<String, Object?>.from(
        PayloadCodec.encodeJsonMap(value, typeName: typeName),
      ),
    );
  }

  /// Report progress with a versioned JSON-serializable DTO payload.
  Future<void> progressVersionedJson<T>(
    double percentComplete,
    T value, {
    required int version,
    String? typeName,
  }) {
    return progress(
      percentComplete,
      data: Map<String, Object?>.from(
        PayloadCodec.encodeVersionedJsonMap(
          value,
          version: version,
          typeName: typeName,
        ),
      ),
    );
  }
}

/// Context passed to handler implementations during execution.
class TaskContext implements TaskExecutionContext {
  /// Creates a task execution context for a handler invocation.
  TaskContext({
    required this.id,
    required this.attempt,
    required this.headers,
    required this.meta,
    required void Function() heartbeat,
    required Future<void> Function(Duration) extendLease,
    required Future<void> Function(
      double percentComplete, {
      Map<String, Object?>? data,
    })
    progress,
    this.cancellation = const TaskCancellationToken.none(),
    this.args = const {},
    this.enqueuer,
    this.workflows,
    this.workflowEvents,
  }) : _heartbeat = heartbeat,
       _extendLease = extendLease,
       _progress = progress;

  /// The unique identifier of the task.
  @override
  final String id;

  @override
  final Map<String, Object?> args;

  /// The current attempt number.
  @override
  final int attempt;

  /// Headers associated with the task.
  @override
  final Map<String, String> headers;

  /// Metadata for the task.
  @override
  final Map<String, Object?> meta;

  @override
  final TaskCancellationToken cancellation;
  final void Function() _heartbeat;
  final Future<void> Function(Duration) _extendLease;
  final Future<void> Function(
    double percentComplete, {
    Map<String, Object?>? data,
  })
  _progress;

  /// Optional enqueuer for scheduling additional tasks.
  final TaskEnqueuer? enqueuer;

  /// Optional workflow caller for starting child workflows.
  final WorkflowCaller? workflows;

  /// Optional workflow event emitter for resuming waiting workflows.
  final WorkflowEventEmitter? workflowEvents;

  @override
  void heartbeat() => _heartbeat();

  @override
  Future<void> extendLease(Duration by) => _extendLease(by);

  @override
  Future<void> progress(double percentComplete, {Map<String, Object?>? data}) =>
      _progress(percentComplete, data: data);

  /// Enqueue a task with default context propagation.
  ///
  /// Headers and metadata from this context are merged into the enqueue
  /// request. Lineage is added to `meta` unless
  /// `enqueueOptions.addToParent` is `false`.
  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    Map<String, Object?> meta = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final delegate = enqueuer;
    if (delegate == null) {
      throw StateError('TaskContext has no enqueuer configured');
    }

    final mergedHeaders = Map<String, String>.from(this.headers)
      ..addAll(headers);
    final scopeMeta = TaskEnqueueScope.currentMeta();
    final mergedMeta = <String, Object?>{
      ...?scopeMeta,
      ...this.meta,
      ...meta,
    };

    if (enqueueOptions?.addToParent ?? true) {
      mergedMeta['stem.parentTaskId'] = id;
      mergedMeta['stem.parentAttempt'] = attempt;
      mergedMeta.putIfAbsent('stem.rootTaskId', () => id);
    }

    return delegate.enqueue(
      name,
      args: args,
      headers: mergedHeaders,
      options: options,
      notBefore: notBefore,
      meta: mergedMeta,
      enqueueOptions: enqueueOptions,
    );
  }

  @override
  Future<String> enqueueValue<T>(
    String name,
    T value, {
    PayloadCodec<T>? codec,
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueue(
      name,
      args: _encodeEnqueuedValue(name, value, codec: codec),
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
  }

  /// Enqueue a typed call with default context propagation.
  ///
  /// This merges headers/meta from the task call and applies lineage metadata
  /// unless `enqueueOptions.addToParent` is `false`.
  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final delegate = enqueuer;
    if (delegate == null) {
      throw StateError('TaskContext has no enqueuer configured');
    }

    final resolvedEnqueueOptions = enqueueOptions ?? call.enqueueOptions;
    final mergedHeaders = Map<String, String>.from(headers)
      ..addAll(call.headers);
    final scopeMeta = TaskEnqueueScope.currentMeta();
    final mergedMeta = <String, Object?>{
      ...?scopeMeta,
      ...meta,
      ...call.meta,
    };

    if (resolvedEnqueueOptions?.addToParent ?? true) {
      mergedMeta['stem.parentTaskId'] = id;
      mergedMeta['stem.parentAttempt'] = attempt;
      mergedMeta.putIfAbsent('stem.rootTaskId', () => id);
    }

    final mergedCall = call.definition.buildCall(
      call.args,
      headers: Map.unmodifiable(mergedHeaders),
      options: call.options,
      notBefore: call.notBefore,
      meta: Map.unmodifiable(mergedMeta),
      enqueueOptions: call.enqueueOptions,
    );

    return delegate.enqueueCall(
      mergedCall,
      enqueueOptions: resolvedEnqueueOptions,
    );
  }

  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) {
    final delegate = workflows;
    if (delegate == null) {
      throw StateError('TaskContext has no workflow caller configured');
    }
    return delegate.startWorkflowRef(
      definition,
      params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) {
    final delegate = workflows;
    if (delegate == null) {
      throw StateError('TaskContext has no workflow caller configured');
    }
    return delegate.startWorkflowCall(call);
  }

  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) {
    final delegate = workflows;
    if (delegate == null) {
      throw StateError('TaskContext has no workflow caller configured');
    }
    return delegate.waitForWorkflowRef(
      runId,
      definition,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }

  @override
  Future<void> emitValue<T>(
    String topic,
    T value, {
    PayloadCodec<T>? codec,
  }) {
    final delegate = workflowEvents;
    if (delegate == null) {
      throw StateError('TaskContext has no workflow event emitter configured');
    }
    return delegate.emitValue(topic, value, codec: codec);
  }

  @override
  Future<void> emitEvent<T>(WorkflowEventRef<T> event, T value) {
    final delegate = workflowEvents;
    if (delegate == null) {
      throw StateError('TaskContext has no workflow event emitter configured');
    }
    return delegate.emitEvent(event, value);
  }

  /// Alias for [enqueue].
  @override
  Future<String> spawn(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    Map<String, Object?> meta = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueue(
      name,
      args: args,
      headers: headers,
      meta: meta,
      options: options,
      notBefore: notBefore,
      enqueueOptions: enqueueOptions,
    );
  }

  /// Request a retry of the current task.
  ///
  /// Throws a [TaskRetryRequest] which is intercepted by the worker to
  /// schedule the retry. Override retry policies/time limits per invocation
  /// by passing the optional parameters.
  @override
  Future<void> retry({
    Duration? countdown,
    DateTime? eta,
    TaskRetryPolicy? retryPolicy,
    int? maxRetries,
    Duration? timeLimit,
    Duration? softTimeLimit,
  }) {
    throw TaskRetryRequest(
      countdown: countdown,
      eta: eta,
      retryPolicy: retryPolicy,
      maxRetries: maxRetries,
      timeLimit: timeLimit,
      softTimeLimit: softTimeLimit,
    );
  }
}

/// Selects the isolate in which a task handler executes.
enum TaskExecutionMode {
  /// Runs the handler in the worker's coordinator isolate.
  ///
  /// A hard time limit stops the worker from awaiting the handler, but Dart
  /// cannot forcibly cancel arbitrary inline asynchronous work. Inline code
  /// should therefore observe [TaskExecutionContext.cancellation] at safe
  /// points when it needs cooperative cancellation.
  inline,

  /// Runs the handler through the worker's managed isolate pool.
  ///
  /// The handler must provide a top-level [TaskEntrypoint]. The worker can
  /// terminate the execution isolate when a hard time limit or hard shutdown
  /// is reached.
  isolate,
}

/// Optional provider for handlers that explicitly declare their execution
/// mode.
abstract interface class TaskExecutionModeProvider {
  /// Declares where the handler executes.
  TaskExecutionMode get executionMode;
}

/// Runtime task handler.
/// Since: 0.1.0
abstract class TaskHandler<R> {
  /// The name of this task handler.
  String get name;

  /// The options for this task handler.
  TaskOptions get options;

  /// Describes the task for tooling and documentation.
  TaskMetadata get metadata => const TaskMetadata();

  /// Executes the task with the given [context] and [args].
  Future<R> call(TaskContext context, Map<String, Object?> args);

  /// Optional entrypoint that allows this task to execute inside an isolate
  /// worker. When `null`, the default execution mode is
  /// [TaskExecutionMode.inline].
  TaskEntrypoint? get isolateEntrypoint => null;
}

/// Resolves the execution mode for a legacy or explicitly-declared handler.
extension TaskHandlerExecutionModeX<R> on TaskHandler<R> {
  /// Returns the explicit mode when the handler provides one, otherwise
  /// preserves the historical entrypoint-based behavior.
  ///
  /// Declaring [TaskExecutionMode.isolate] without an entrypoint is rejected
  /// by the worker with a descriptive error.
  TaskExecutionMode get executionMode {
    final provider = this;
    if (provider is TaskExecutionModeProvider) {
      return (provider as TaskExecutionModeProvider).executionMode;
    }
    return isolateEntrypoint == null
        ? TaskExecutionMode.inline
        : TaskExecutionMode.isolate;
  }
}

/// Typed task handler for the recommended manual registration path.
///
/// The runtime still lowers task arguments to the durable map transport, but
/// application code receives [TArgs] and returns [TResult]. Generated task
/// adapters can use the same contract while keeping transport decoding out of
/// user code.
class TypedTaskHandler<TArgs, TResult>
    implements TaskHandler<TResult>, TaskExecutionModeProvider {
  /// Creates a typed task handler backed by [definition].
  const TypedTaskHandler({
    required this.definition,
    required this.entrypoint,
    this.argsDecoder,
    this.isolateEntrypoint,
    TaskExecutionMode? executionMode,
  }) : _executionMode = executionMode;

  /// Typed task definition used for naming, options, metadata, and results.
  final TaskDefinition<TArgs, TResult> definition;

  /// Typed application handler.
  final Future<TResult> Function(TaskExecutionContext context, TArgs args)
  entrypoint;

  /// Optional decoder for definitions that only provide an encoder.
  final TaskArgsDecoder<TArgs>? argsDecoder;

  @override
  String get name => definition.name;

  @override
  TaskOptions get options => definition.defaultOptions;

  @override
  TaskMetadata get metadata => definition.metadata;

  /// Optional top-level adapter used when the task is dispatched to an
  /// execution isolate. Generated handlers provide this adapter so the
  /// durable map transport is decoded inside the child isolate.
  @override
  final TaskEntrypoint? isolateEntrypoint;

  final TaskExecutionMode? _executionMode;

  /// Explicit execution mode, or the mode inferred from
  /// [isolateEntrypoint] when omitted.
  @override
  TaskExecutionMode get executionMode =>
      _executionMode ??
      (isolateEntrypoint == null
          ? TaskExecutionMode.inline
          : TaskExecutionMode.isolate);

  @override
  Future<TResult> call(TaskContext context, Map<String, Object?> args) async {
    final decoder = argsDecoder ?? definition.decodeArgs;
    if (decoder == null) {
      throw StateError(
        'Task definition "${definition.name}" does not provide an argument '
        'decoder for TypedTaskHandler.',
      );
    }
    return entrypoint(context, decoder(args));
  }
}

/// Registry mapping task names to handler implementations.
abstract class TaskRegistry {
  /// Registers the [handler] with this registry.
  void register(TaskHandler<Object?> handler, {bool overrideExisting = false});

  /// Resolves the handler for the given [name], or null if not found.
  TaskHandler<Object?>? resolve(String name);

  /// All handlers currently registered.
  Iterable<TaskHandler<Object?>> get handlers;

  /// Stream of registration events for observers.
  Stream<TaskRegistrationEvent> get onRegister;
}

/// Default in-memory registry implementation.
class InMemoryTaskRegistry implements TaskRegistry {
  final Map<String, TaskHandler<Object?>> _handlers = {};
  final StreamController<TaskRegistrationEvent> _registerController =
      StreamController<TaskRegistrationEvent>.broadcast();

  /// Registers the [handler] in this registry.
  @override
  void register(TaskHandler<Object?> handler, {bool overrideExisting = false}) {
    final existing = _handlers[handler.name];
    if (existing != null && !overrideExisting) {
      throw ArgumentError(
        'Task handler "${handler.name}" is already registered.',
      );
    }
    _handlers[handler.name] = handler;
    _registerController.add(
      TaskRegistrationEvent(
        name: handler.name,
        handler: handler,
        overridden: existing != null,
      ),
    );
  }

  /// Resolves the handler for the given [name], or returns null if not found.
  @override
  TaskHandler<Object?>? resolve(String name) => _handlers[name];

  @override
  Iterable<TaskHandler<Object?>> get handlers =>
      UnmodifiableListView(_handlers.values);

  @override
  Stream<TaskRegistrationEvent> get onRegister => _registerController.stream;
}

/// Optional task metadata for documentation and tooling.
class TaskMetadata {
  /// Creates task metadata for documentation and tooling.
  const TaskMetadata({
    this.description,
    this.tags = const [],
    this.idempotent = false,
    this.attributes = const {},
    this.resultEncoder,
    this.argsEncoder,
  });

  /// Human-readable description of the task.
  final String? description;

  /// Arbitrary tags that describe behavior (e.g. "idempotent", "critical").
  final List<String> tags;

  /// Whether the task is safe to execute multiple times with the same args.
  final bool idempotent;

  /// Additional metadata for tooling and dashboards.
  final Map<String, Object?> attributes;

  /// Optional result encoder override applied when persisting handler return
  /// values. When null the runtime falls back to the configured default.
  final TaskPayloadEncoder? resultEncoder;

  /// Optional argument encoder override applied when publishing envelopes for
  /// this task. When null the runtime falls back to the configured default.
  final TaskPayloadEncoder? argsEncoder;
}

/// Encodes strongly typed task arguments into a JSON-ready map.
typedef TaskArgsEncoder<TArgs> = Map<String, Object?> Function(TArgs args);

/// Decodes persisted task arguments into the typed handler input.
typedef TaskArgsDecoder<TArgs> = TArgs Function(Map<String, Object?> args);

/// Builds metadata for a task invocation using its arguments.
typedef TaskMetaBuilder<TArgs> = Map<String, Object?> Function(TArgs args);

/// Decodes a persisted task result payload into a typed value.
typedef TaskResultDecoder<TResult> = TResult Function(Object? payload);

/// Event emitted when a task handler registers with a registry.
class TaskRegistrationEvent {
  /// Creates a registration event snapshot.
  const TaskRegistrationEvent({
    required this.name,
    required this.handler,
    required this.overridden,
  });

  /// Logical task name.
  final String name;

  /// Handler implementation that was registered.
  final TaskHandler<Object?> handler;

  /// Whether this registration replaced a previous handler.
  final bool overridden;
}

/// Declarative task definition to build typed enqueue calls.
class TaskDefinition<TArgs, TResult> {
  /// Creates a typed task definition with encoding/decoding hooks.
  const TaskDefinition({
    required this.name,
    required TaskArgsEncoder<TArgs> encodeArgs,
    this.decodeArgs,
    TaskMetaBuilder<TArgs>? encodeMeta,
    this.defaultOptions = const TaskOptions(),
    this.metadata = const TaskMetadata(),
    this.decodeResult,
  }) : _encodeArgs = encodeArgs,
       _encodeMeta = encodeMeta;

  /// Creates a typed task definition backed by payload codecs.
  factory TaskDefinition.codec({
    required String name,
    required PayloadCodec<TArgs> argsCodec,
    TaskMetaBuilder<TArgs>? encodeMeta,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    PayloadCodec<TResult>? resultCodec,
  }) {
    return TaskDefinition<TArgs, TResult>(
      name: name,
      encodeArgs: (args) => _encodeCodecArgs(name, argsCodec, args),
      decodeArgs: (args) => argsCodec.decode(args),
      encodeMeta: encodeMeta,
      defaultOptions: defaultOptions,
      metadata: _metadataWithResultCodec(name, metadata, resultCodec),
      decodeResult: resultCodec?.decode,
    );
  }

  /// Creates a typed task definition for DTO args that already expose
  /// `toJson()`.
  factory TaskDefinition.json({
    required String name,
    TArgs Function(Map<String, dynamic> payload)? decodeArgsJson,
    TArgs Function(Map<String, dynamic> payload, int version)?
    decodeArgsVersionedJson,
    TaskMetaBuilder<TArgs>? encodeMeta,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    TResult Function(Map<String, dynamic> payload)? decodeResultJson,
    TResult Function(Map<String, dynamic> payload, int version)?
    decodeResultVersionedJson,
    int? defaultDecodeVersion,
    String? argsTypeName,
    String? resultTypeName,
  }) {
    assert(
      decodeResultJson == null || decodeResultVersionedJson == null,
      'Specify either decodeResultJson or decodeResultVersionedJson, not both.',
    );
    assert(
      decodeArgsJson == null || decodeArgsVersionedJson == null,
      'Specify either decodeArgsJson or decodeArgsVersionedJson, not both.',
    );
    final argsCodec = decodeArgsVersionedJson != null
        ? PayloadCodec<TArgs>.versionedJson(
            version: defaultDecodeVersion ?? 1,
            decode: decodeArgsVersionedJson,
            defaultDecodeVersion: defaultDecodeVersion,
            typeName: argsTypeName ?? '$TArgs',
          )
        : (decodeArgsJson == null
              ? null
              : PayloadCodec<TArgs>.json(
                  decode: decodeArgsJson,
                  typeName: argsTypeName ?? '$TArgs',
                ));
    final resultCodec = decodeResultVersionedJson != null
        ? PayloadCodec<TResult>.versionedJson(
            version: defaultDecodeVersion ?? 1,
            decode: decodeResultVersionedJson,
            defaultDecodeVersion: defaultDecodeVersion,
            typeName: resultTypeName ?? '$TResult',
          )
        : (decodeResultJson == null
              ? null
              : PayloadCodec<TResult>.json(
                  decode: decodeResultJson,
                  typeName: resultTypeName ?? '$TResult',
                ));
    return TaskDefinition<TArgs, TResult>(
      name: name,
      encodeArgs: (args) => _encodeJsonArgs(args, argsTypeName ?? '$TArgs'),
      decodeArgs: argsCodec?.decode,
      encodeMeta: encodeMeta,
      defaultOptions: defaultOptions,
      metadata: _metadataWithResultCodec(name, metadata, resultCodec),
      decodeResult: resultCodec?.decode,
    );
  }

  /// Creates a typed task definition for DTO args that already expose
  /// `toJson()` and persist a schema [version] beside the payload.
  factory TaskDefinition.versionedJson({
    required String name,
    required int version,
    TArgs Function(Map<String, dynamic> payload)? decodeArgsJson,
    TArgs Function(Map<String, dynamic> payload, int version)?
    decodeArgsVersionedJson,
    TaskMetaBuilder<TArgs>? encodeMeta,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    TResult Function(Map<String, dynamic> payload)? decodeResultJson,
    TResult Function(Map<String, dynamic> payload, int version)?
    decodeResultVersionedJson,
    int? defaultDecodeVersion,
    String? argsTypeName,
    String? resultTypeName,
  }) {
    assert(
      decodeResultJson == null || decodeResultVersionedJson == null,
      'Specify either decodeResultJson or decodeResultVersionedJson, not both.',
    );
    assert(
      decodeArgsJson == null || decodeArgsVersionedJson == null,
      'Specify either decodeArgsJson or decodeArgsVersionedJson, not both.',
    );
    final argsCodec = decodeArgsVersionedJson != null
        ? PayloadCodec<TArgs>.versionedJson(
            version: version,
            decode: decodeArgsVersionedJson,
            defaultDecodeVersion: defaultDecodeVersion,
            typeName: argsTypeName ?? '$TArgs',
          )
        : (decodeArgsJson == null
              ? null
              : PayloadCodec<TArgs>.json(
                  decode: decodeArgsJson,
                  typeName: argsTypeName ?? '$TArgs',
                ));
    final resultCodec = decodeResultVersionedJson != null
        ? PayloadCodec<TResult>.versionedJson(
            version: version,
            decode: decodeResultVersionedJson,
            defaultDecodeVersion: defaultDecodeVersion,
            typeName: resultTypeName ?? '$TResult',
          )
        : (decodeResultJson == null
              ? null
              : PayloadCodec<TResult>.json(
                  decode: decodeResultJson,
                  typeName: resultTypeName ?? '$TResult',
                ));
    return TaskDefinition<TArgs, TResult>(
      name: name,
      encodeArgs: (args) => _encodeVersionedJsonArgs(
        args,
        version: version,
        typeName: argsTypeName ?? '$TArgs',
      ),
      decodeArgs: argsCodec?.decode,
      encodeMeta: encodeMeta,
      defaultOptions: defaultOptions,
      metadata: _metadataWithResultCodec(name, metadata, resultCodec),
      decodeResult: resultCodec?.decode,
    );
  }

  /// Creates a typed task definition for DTO args that already expose
  /// `toJson()` and decode versioned results through a reusable registry.
  factory TaskDefinition.versionedJsonRegistry({
    required String name,
    required int version,
    required PayloadVersionRegistry<TResult> resultRegistry,
    TaskMetaBuilder<TArgs>? encodeMeta,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    int? defaultDecodeVersion,
    String? argsTypeName,
    String? resultTypeName,
  }) {
    return TaskDefinition<TArgs, TResult>(
      name: name,
      encodeArgs: (args) => _encodeVersionedJsonArgs(
        args,
        version: version,
        typeName: argsTypeName ?? '$TArgs',
      ),
      encodeMeta: encodeMeta,
      defaultOptions: defaultOptions,
      metadata: _metadataWithResultCodec(
        name,
        metadata,
        PayloadCodec<TResult>.versionedJsonRegistry(
          version: version,
          registry: resultRegistry,
          defaultDecodeVersion: defaultDecodeVersion,
          typeName: resultTypeName ?? '$TResult',
        ),
      ),
      decodeResult: PayloadCodec<TResult>.versionedJsonRegistry(
        version: version,
        registry: resultRegistry,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: resultTypeName ?? '$TResult',
      ).decode,
    );
  }

  /// Creates a typed task definition for custom map args that persist a schema
  /// [version] beside the payload.
  factory TaskDefinition.versionedMap({
    required String name,
    required Object? Function(TArgs args) encodeArgs,
    required int version,
    TaskMetaBuilder<TArgs>? encodeMeta,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    TResult Function(Map<String, dynamic> payload)? decodeResultJson,
    TResult Function(Map<String, dynamic> payload, int version)?
    decodeResultVersionedJson,
    int? defaultDecodeVersion,
    String? argsTypeName,
    String? resultTypeName,
  }) {
    assert(
      decodeResultJson == null || decodeResultVersionedJson == null,
      'Specify either decodeResultJson or decodeResultVersionedJson, not both.',
    );
    final argsCodec = PayloadCodec<TArgs>.versionedMap(
      encode: encodeArgs,
      version: version,
      decode: (payload, _) => throw UnsupportedError(
        'TaskDefinition.versionedMap($name) only uses the args codec for '
        'encoding. Decoding is not supported at the definition layer.',
      ),
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: argsTypeName ?? '$TArgs',
    );
    final resultCodec = decodeResultVersionedJson != null
        ? PayloadCodec<TResult>.versionedJson(
            version: version,
            decode: decodeResultVersionedJson,
            defaultDecodeVersion: defaultDecodeVersion,
            typeName: resultTypeName ?? '$TResult',
          )
        : (decodeResultJson == null
              ? null
              : PayloadCodec<TResult>.json(
                  decode: decodeResultJson,
                  typeName: resultTypeName ?? '$TResult',
                ));
    return TaskDefinition<TArgs, TResult>.codec(
      name: name,
      argsCodec: argsCodec,
      encodeMeta: encodeMeta,
      defaultOptions: defaultOptions,
      metadata: metadata,
      resultCodec: resultCodec,
    );
  }

  /// Creates a typed task definition for custom map args that persist a schema
  /// [version] and decode versioned results through a reusable registry.
  factory TaskDefinition.versionedMapRegistry({
    required String name,
    required Object? Function(TArgs args) encodeArgs,
    required int version,
    required PayloadVersionRegistry<TResult> resultRegistry,
    TaskMetaBuilder<TArgs>? encodeMeta,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    int? defaultDecodeVersion,
    String? argsTypeName,
    String? resultTypeName,
  }) {
    final argsCodec = PayloadCodec<TArgs>.versionedMap(
      encode: encodeArgs,
      version: version,
      decode: (payload, _) => throw UnsupportedError(
        'TaskDefinition.versionedMapRegistry($name) only uses the args codec '
        'for encoding. Decoding is not supported at the definition layer.',
      ),
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: argsTypeName ?? '$TArgs',
    );
    final resultCodec = PayloadCodec<TResult>.versionedJsonRegistry(
      version: version,
      registry: resultRegistry,
      defaultDecodeVersion: defaultDecodeVersion,
      typeName: resultTypeName ?? '$TResult',
    );
    return TaskDefinition<TArgs, TResult>.codec(
      name: name,
      argsCodec: argsCodec,
      encodeMeta: encodeMeta,
      defaultOptions: defaultOptions,
      metadata: metadata,
      resultCodec: resultCodec,
    );
  }

  /// Creates a typed task definition for handlers with no producer args.
  static NoArgsTaskDefinition<TResult> noArgsCodec<TResult>({
    required String name,
    required PayloadCodec<TResult> resultCodec,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
  }) {
    return noArgs<TResult>(
      name: name,
      defaultOptions: defaultOptions,
      metadata: metadata,
      resultCodec: resultCodec,
    );
  }

  /// Creates a typed task definition for handlers with no producer args.
  static NoArgsTaskDefinition<TResult> noArgsJson<TResult>({
    required String name,
    required TResult Function(Map<String, dynamic> payload) decodeResult,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    String? resultTypeName,
  }) {
    return noArgs<TResult>(
      name: name,
      defaultOptions: defaultOptions,
      metadata: metadata,
      decodeResultJson: decodeResult,
      resultTypeName: resultTypeName,
    );
  }

  /// Creates a typed task definition for handlers with no producer args whose
  /// result is a versioned DTO-backed JSON value.
  static NoArgsTaskDefinition<TResult> noArgsVersionedJson<TResult>({
    required String name,
    required int version,
    required TResult Function(Map<String, dynamic> payload, int version)
    decodeResult,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    int? defaultDecodeVersion,
    String? resultTypeName,
  }) {
    return noArgs<TResult>(
      name: name,
      defaultOptions: defaultOptions,
      metadata: metadata,
      resultCodec: PayloadCodec<TResult>.versionedJson(
        version: version,
        decode: decodeResult,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: resultTypeName ?? '$TResult',
      ),
    );
  }

  /// Creates a typed task definition for handlers with no producer args whose
  /// result uses a reusable version registry.
  static NoArgsTaskDefinition<TResult> noArgsVersionedJsonRegistry<TResult>({
    required String name,
    required int version,
    required PayloadVersionRegistry<TResult> resultRegistry,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    int? defaultDecodeVersion,
    String? resultTypeName,
  }) {
    return noArgs<TResult>(
      name: name,
      defaultOptions: defaultOptions,
      metadata: metadata,
      resultCodec: PayloadCodec<TResult>.versionedJsonRegistry(
        version: version,
        registry: resultRegistry,
        defaultDecodeVersion: defaultDecodeVersion,
        typeName: resultTypeName ?? '$TResult',
      ),
    );
  }

  /// Creates a typed task definition for handlers with no producer args.
  static NoArgsTaskDefinition<TResult> noArgs<TResult>({
    required String name,
    TaskOptions defaultOptions = const TaskOptions(),
    TaskMetadata metadata = const TaskMetadata(),
    TaskResultDecoder<TResult>? decodeResult,
    PayloadCodec<TResult>? resultCodec,
    TResult Function(Map<String, dynamic> payload)? decodeResultJson,
    String? resultTypeName,
  }) {
    assert(
      resultCodec == null || decodeResultJson == null,
      'Specify either resultCodec or decodeResultJson, not both.',
    );
    final resolvedResultCodec =
        resultCodec ??
        (decodeResultJson == null
            ? null
            : PayloadCodec<TResult>.json(
                decode: decodeResultJson,
                typeName: resultTypeName ?? '$TResult',
              ));
    return NoArgsTaskDefinition<TResult>(
      name: name,
      defaultOptions: defaultOptions,
      metadata: TaskDefinition._metadataWithResultCodec(
        name,
        metadata,
        resolvedResultCodec,
      ),
      decodeResult: decodeResult ?? resolvedResultCodec?.decode,
    );
  }

  /// The logical task name registered in the registry.
  final String name;

  /// Default options applied to every call unless overridden.
  final TaskOptions defaultOptions;

  /// Metadata associated with this task for documentation/tooling.
  final TaskMetadata metadata;

  /// Optional decoder for converting persisted payloads into a typed result.
  final TaskResultDecoder<TResult>? decodeResult;

  /// Optional decoder used by typed handler adapters.
  final TaskArgsDecoder<TArgs>? decodeArgs;

  final TaskArgsEncoder<TArgs> _encodeArgs;
  final TaskMetaBuilder<TArgs>? _encodeMeta;

  static Map<String, Object?> _encodeCodecArgs<T>(
    String taskName,
    PayloadCodec<T> codec,
    T args,
  ) {
    return _encodeEnqueuedValue(taskName, args, codec: codec);
  }

  static Map<String, Object?> _encodeJsonArgs<T>(T args, String typeName) {
    final payload = PayloadCodec.encodeJsonMap(
      args,
      typeName: typeName,
    );
    return Map<String, Object?>.from(payload);
  }

  static Map<String, Object?> _encodeVersionedJsonArgs<T>(
    T args, {
    required int version,
    required String typeName,
  }) {
    final payload = PayloadCodec.encodeVersionedJsonMap(
      args,
      version: version,
      typeName: typeName,
    );
    return Map<String, Object?>.from(payload);
  }

  static TaskMetadata _metadataWithResultCodec<TResult>(
    String taskName,
    TaskMetadata metadata,
    PayloadCodec<TResult>? resultCodec,
  ) {
    if (resultCodec == null) {
      return metadata;
    }
    return TaskMetadata(
      description: metadata.description,
      tags: metadata.tags,
      idempotent: metadata.idempotent,
      attributes: metadata.attributes,
      argsEncoder: metadata.argsEncoder,
      resultEncoder:
          metadata.resultEncoder ??
          CodecTaskPayloadEncoder<TResult>(
            idValue: '$taskName.result.codec',
            codec: resultCodec,
          ),
    );
  }

  /// Builds an explicit [TaskCall] from this definition and [args].
  TaskCall<TArgs, TResult> buildCall(
    TArgs args, {
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TaskEnqueueOptions? enqueueOptions,
  }) {
    final metaBuilder = _encodeMeta;
    final resolvedMeta =
        meta ?? (metaBuilder != null ? metaBuilder(args) : const {});
    return TaskCall._(
      definition: this,
      args: args,
      headers: Map.unmodifiable(headers),
      options: options,
      notBefore: notBefore,
      meta: Map.unmodifiable(resolvedMeta),
      enqueueOptions: enqueueOptions,
    );
  }

  /// Encodes arguments into a JSON-ready map.
  Map<String, Object?> encodeArgs(TArgs args) => _encodeArgs(args);

  /// Creates a typed inline handler for this definition.
  ///
  /// When [executionMode] is omitted, the mode is inferred from
  /// [isolateEntrypoint]. Set it explicitly when the execution guarantee is
  /// part of the task's contract.
  TypedTaskHandler<TArgs, TResult> handler({
    required Future<TResult> Function(TaskExecutionContext context, TArgs args)
    entrypoint,
    TaskArgsDecoder<TArgs>? argsDecoder,
    TaskEntrypoint? isolateEntrypoint,
    TaskExecutionMode? executionMode,
  }) {
    return TypedTaskHandler<TArgs, TResult>(
      definition: this,
      entrypoint: entrypoint,
      argsDecoder: argsDecoder,
      isolateEntrypoint: isolateEntrypoint,
      executionMode: executionMode,
    );
  }

  /// Builds metadata for the given arguments.
  Map<String, Object?> encodeMeta(TArgs args) {
    final metaBuilder = _encodeMeta;
    return metaBuilder != null ? metaBuilder(args) : const {};
  }

  /// Decodes a persisted payload into a typed result.
  TResult? decode(Object? payload) {
    if (payload == null) return null;
    final decoder = decodeResult;
    if (decoder != null) {
      return decoder(payload);
    }
    return payload as TResult?;
  }
}

/// Typed producer-facing definition for tasks that take no input args.
class NoArgsTaskDefinition<TResult> {
  /// Creates a typed task definition for handlers with no producer args.
  const NoArgsTaskDefinition({
    required this.name,
    this.defaultOptions = const TaskOptions(),
    this.metadata = const TaskMetadata(),
    this.decodeResult,
  });

  /// The logical task name registered in the registry.
  final String name;

  /// Default options applied to every call unless overridden.
  final TaskOptions defaultOptions;

  /// Metadata associated with this task for documentation/tooling.
  final TaskMetadata metadata;

  /// Optional decoder for converting persisted payloads into a typed result.
  final TaskResultDecoder<TResult>? decodeResult;

  /// The underlying task definition for generic enqueue/wait surfaces.
  TaskDefinition<(), TResult> get asDefinition => TaskDefinition<(), TResult>(
    name: name,
    encodeArgs: (_) => const <String, Object?>{},
    decodeArgs: (_) => const (),
    defaultOptions: defaultOptions,
    metadata: metadata,
    decodeResult: decodeResult,
  );

  /// Decodes a persisted payload into a typed result.
  TResult? decode(Object? payload) => asDefinition.decode(payload);

  /// Creates a typed handler for a task that takes no input arguments.
  ///
  /// When [executionMode] is omitted, the mode is inferred from
  /// [isolateEntrypoint].
  TypedTaskHandler<(), TResult> handler({
    required Future<TResult> Function(TaskExecutionContext context, ())
    entrypoint,
    TaskEntrypoint? isolateEntrypoint,
    TaskExecutionMode? executionMode,
  }) {
    return asDefinition.handler(
      entrypoint: entrypoint,
      isolateEntrypoint: isolateEntrypoint,
      executionMode: executionMode,
    );
  }
}

/// Represents a pending enqueue operation built from a [TaskDefinition].
class TaskCall<TArgs, TResult> {
  const TaskCall._({
    required this.definition,
    required this.args,
    required this.headers,
    required this.meta,
    this.options,
    this.notBefore,
    this.enqueueOptions,
  });

  /// The task definition this call was derived from.
  final TaskDefinition<TArgs, TResult> definition;

  /// Typed arguments for the task invocation.
  final TArgs args;

  /// Headers attached to the outbound envelope.
  final Map<String, String> headers;

  /// Optional task options override for this call.
  final TaskOptions? options;

  /// Optional schedule time for delayed execution.
  final DateTime? notBefore;

  /// Optional enqueue options for this call.
  final TaskEnqueueOptions? enqueueOptions;

  /// Metadata associated with this invocation.
  final Map<String, Object?> meta;

  /// Task name resolved from the definition.
  String get name => definition.name;

  /// Encoded arguments ready for enqueue.
  Map<String, Object?> encodeArgs() => definition.encodeArgs(args);

  /// Resolve final options combining call overrides with defaults.
  TaskOptions resolveOptions() => options ?? definition.defaultOptions;
}

/// Convenience helpers for building typed enqueue requests directly from a task
/// enqueuer.
extension TaskEnqueuerBuilderExtension on TaskEnqueuer {
  /// Enqueues a name-based task from a DTO that already exposes `toJson()`.
  Future<String> enqueueJson<T extends Object>(
    String name,
    T argsJson, {
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
    String? typeName,
  }) {
    return enqueue(
      name,
      args: Map<String, Object?>.from(
        PayloadCodec.encodeJsonMap(
          argsJson,
          typeName: typeName ?? '$T',
        ),
      ),
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
  }

  /// Enqueues a name-based task from a DTO and persists a schema [version]
  /// beside the JSON payload.
  Future<String> enqueueVersionedJson<T extends Object>(
    String name,
    T argsJson, {
    required int version,
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
    String? typeName,
  }) {
    return enqueue(
      name,
      args: Map<String, Object?>.from(
        PayloadCodec.encodeVersionedJsonMap(
          argsJson,
          version: version,
          typeName: typeName ?? '$T',
        ),
      ),
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
  }
}

/// Retry strategy used to compute the next backoff delay.
/// Since: 0.1.0
// Intentionally an interface for DI and test doubles.
// ignore: one_member_abstracts
abstract class RetryStrategy {
  /// Computes the next delay duration for [attempt], [error], and [stackTrace].
  Duration nextDelay(int attempt, Object error, StackTrace stackTrace);
}

/// Typed rate-limit configuration shared across workers.
/// Since: 0.3.0
@immutable
class RateLimit {
  /// Creates a rate limit allowing [tokens] acquisitions per [interval].
  const RateLimit({required this.tokens, required this.interval})
    : assert(tokens > 0, 'tokens must be positive');

  /// Creates a per-second rate limit.
  const RateLimit.perSecond(int tokens)
    : this(tokens: tokens, interval: const Duration(seconds: 1));

  /// Creates a per-minute rate limit.
  const RateLimit.perMinute(int tokens)
    : this(tokens: tokens, interval: const Duration(minutes: 1));

  /// Creates a per-hour rate limit.
  const RateLimit.perHour(int tokens)
    : this(tokens: tokens, interval: const Duration(hours: 1));

  /// Parses the legacy `10/s`, `10/m` or `10/h` representation.
  ///
  /// This is intentionally retained for JSON, YAML and environment
  /// configuration. Dart code should prefer the typed constructors.
  static RateLimit? parse(Object? value) {
    if (value == null) return null;
    if (value is RateLimit) return value;
    final raw = value.toString().trim().toLowerCase();
    final parts = raw.split('/');
    if (parts.length != 2) return null;
    final tokens = int.tryParse(parts[0]);
    if (tokens == null || tokens <= 0) return null;
    final interval = switch (parts[1]) {
      's' => const Duration(seconds: 1),
      'm' => const Duration(minutes: 1),
      'h' => const Duration(hours: 1),
      _ => null,
    };
    return interval == null
        ? null
        : RateLimit(tokens: tokens, interval: interval);
  }

  /// Maximum number of tokens granted in [interval].
  final int tokens;

  /// Window over which [tokens] are granted.
  final Duration interval;

  @override
  String toString() {
    final suffix = interval == const Duration(seconds: 1)
        ? 's'
        : interval == const Duration(minutes: 1)
        ? 'm'
        : interval == const Duration(hours: 1)
        ? 'h'
        : interval.toString();
    return '$tokens/$suffix';
  }

  @override
  bool operator ==(Object other) =>
      other is RateLimit &&
      other.tokens == tokens &&
      other.interval == interval;

  @override
  int get hashCode => Object.hash(tokens, interval);
}

/// Optional rate limiter interface shared across workers.
/// Since: 0.1.0
// Intentionally an interface for DI and test doubles.
// ignore: one_member_abstracts
abstract class RateLimiter {
  /// Attempts to acquire [tokens] for [key], with optional [interval] and
  /// [meta].
  Future<RateLimitDecision> acquire(
    String key, {
    int tokens = 1,
    Duration? interval,
    Map<String, Object?>? meta,
  });
}

/// Defines behavior when a limiter backend call fails.
enum RateLimiterFailureMode {
  /// Continue executing even when limiter calls fail.
  failOpen,

  /// Block execution and retry later when limiter calls fail.
  failClosed,
}

/// Result of attempting to acquire tokens from the rate limiter.
class RateLimitDecision {
  /// Creates a rate limit decision outcome.
  const RateLimitDecision({
    required this.allowed,
    this.retryAfter,
    this.meta = const {},
  });

  /// Whether the acquisition was allowed.
  final bool allowed;

  /// The duration to wait before retrying, if not allowed.
  final Duration? retryAfter;

  /// Additional metadata for the decision.
  final Map<String, Object?> meta;
}

/// Lock store used for unique jobs or scheduling coordination.
/// Since: 0.1.0
abstract class LockStore {
  /// Attempts to acquire a lock for [key], with [ttl] and optional [owner].
  Future<Lock?> acquire(
    String key, {
    Duration ttl = const Duration(seconds: 30),
    String? owner,
  });

  /// Renews the lock for [key] when held by [owner], extending by [ttl].
  ///
  /// Returns `true` when the lock was renewed, otherwise `false` (e.g. owner
  /// mismatch or lock expired).
  Future<bool> renew(String key, String owner, Duration ttl);

  /// Returns the owner currently holding the lock for [key], or null if
  /// unlocked.
  Future<String?> ownerOf(String key);

  /// Releases the lock identified by [key] if held by [owner].
  ///
  /// Returns `true` when the lock was released, otherwise `false` (e.g. owner
  /// mismatch or already expired).
  Future<bool> release(String key, String owner);
}

/// Handle to a lock acquired from a [LockStore].
abstract class Lock {
  /// The key of this lock.
  String get key;

  /// The owner identifier of this lock.
  String get owner;

  /// Renews this lock with a new [ttl], returning whether successful.
  Future<bool> renew(Duration ttl);

  /// Releases this lock.
  Future<void> release();
}

/// A lock handle that carries a monotonically increasing fencing token.
///
/// The token identifies the acquisition, not merely the owner process. A
/// downstream storage system can reject writes carrying an older token after
/// a lease has expired and been acquired by another process. Implementations
/// of [LockStore] that cannot provide a durable token may continue returning
/// the base [Lock] contract.
abstract interface class FencedLock implements Lock {
  /// Token for this specific lock acquisition.
  int get fencingToken;
}

/// Provides the fencing token when a lock implementation supports fencing.
extension LockFencingTokenX on Lock {
  /// The acquisition token, or `null` for legacy lock implementations.
  int? get fencingToken =>
      this is FencedLock ? (this as FencedLock).fencingToken : null;
}

/// Middleware hook invoked for lifecycle events around enqueue/consume/execute.
/// Since: 0.1.0
abstract class Middleware {
  /// Called when enqueuing an [envelope]. Call [next] to proceed.
  Future<void> onEnqueue(Envelope envelope, Future<void> Function() next);

  /// Called when consuming a [delivery]. Call [next] to proceed.
  Future<void> onConsume(Delivery delivery, Future<void> Function() next);

  /// Called when executing a task with [context]. Call [next] to proceed.
  Future<void> onExecute(TaskContext context, Future<void> Function() next);

  /// Called when an error occurs during task execution.
  Future<void> onError(
    TaskContext context,
    Object error,
    StackTrace stackTrace,
  );
}

/// Descriptor for group (e.g., chord) aggregation.
class GroupDescriptor {
  /// Creates a group descriptor for chord aggregation.
  GroupDescriptor({
    required this.id,
    required this.expected,
    Map<String, Object?>? meta,
    this.ttl,
  }) : meta = Map.unmodifiable(meta ?? const {});

  /// The unique identifier of the group.
  final String id;

  /// The expected number of results.
  final int expected;

  /// Additional metadata for the group.
  final Map<String, Object?> meta;

  /// The time-to-live for the group.
  final Duration? ttl;
}

/// Aggregated status for a group/chord.
class GroupStatus {
  /// Creates a group status snapshot.
  GroupStatus({
    required this.id,
    required this.expected,
    Map<String, TaskStatus>? results,
    Map<String, Object?>? meta,
  }) : results = Map.unmodifiable(results ?? const {}),
       meta = Map.unmodifiable(meta ?? const {});

  /// The unique identifier of the group.
  final String id;

  /// The expected number of results.
  final int expected;

  /// The results collected so far.
  final Map<String, TaskStatus> results;

  /// Additional metadata for the group.
  final Map<String, Object?> meta;

  /// Returns the decoded payload value for each collected child result.
  ///
  /// When [codec] is supplied, each stored durable payload is decoded through
  /// that codec before being returned.
  Map<String, T?> resultValues<T>({PayloadCodec<T>? codec}) {
    return Map.unmodifiable({
      for (final entry in results.entries)
        entry.key: entry.value.payloadValue<T>(codec: codec),
    });
  }

  /// Decodes each collected child result as a typed DTO with [codec].
  Map<String, T?> resultAs<T>({required PayloadCodec<T> codec}) {
    return Map.unmodifiable({
      for (final entry in results.entries)
        entry.key: entry.value.payloadAs(codec: codec),
    });
  }

  /// Decodes each collected child result as a typed DTO with a JSON decoder.
  Map<String, T?> resultJson<T>({
    required T Function(Map<String, dynamic> payload) decode,
    String? typeName,
  }) {
    return Map.unmodifiable({
      for (final entry in results.entries)
        entry.key: entry.value.payloadJson(
          decode: decode,
          typeName: typeName,
        ),
    });
  }

  /// Decodes each collected child result as a typed DTO with a version-aware
  /// JSON decoder.
  Map<String, T?> resultVersionedJson<T>({
    required int version,
    required T Function(Map<String, dynamic> payload, int version) decode,
    int? defaultDecodeVersion,
    String? typeName,
  }) {
    return Map.unmodifiable({
      for (final entry in results.entries)
        entry.key: entry.value.payloadVersionedJson(
          version: version,
          decode: decode,
          defaultDecodeVersion: defaultDecodeVersion,
          typeName: typeName,
        ),
    });
  }

  /// The number of completed results.
  int get completed => results.length;

  /// Whether the group is complete.
  bool get isComplete => completed >= expected;
}
