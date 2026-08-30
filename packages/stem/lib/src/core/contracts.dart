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
    int 