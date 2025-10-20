import 'dart:async';

import 'envelope.dart';
import 'task_invocation.dart';

/// Abstract broker interface implemented by queue adapters (Redis, SQS, etc).
abstract class Broker {
  /// Publishes the given [envelope] to the specified [queue].
  ///
  /// If [queue] is omitted, publishes to the default queue.
  Future<void> publish(Envelope envelope, {String? queue});

  /// Returns a stream of deliveries from the [queue].
  ///
  /// The [prefetch] parameter specifies the number of messages to prefetch.
  /// [consumerGroup] and [consumerName] can be used for consumer identification.
  Stream<Delivery> consume(
    String queue, {
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

  /// Sends the [delivery] to the dead letter queue.
  ///
  /// [reason] provides the reason for dead lettering, and [meta] additional data.
  Future<void> deadLetter(
    Delivery delivery, {
    String? reason,
    Map<String, Object?>? meta,
  });

  /// Removes all messages from the [queue].
  Future<void> purge(String queue);

  /// Extends the lease for the [delivery] by the [by] duration.
  Future<void> extendLease(Delivery delivery, Duration by);

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
  });

  /// Retrieves a single dead letter entry by envelope [id], or `null` if not
  /// found.
  Future<DeadLetterEntry?> getDeadLetter(String queue, String id);

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
  });

  /// Removes dead letter entries from [queue].
  ///
  /// When [since] is provided, only entries with `deadAt` greater than or equal
  /// to the timestamp must be removed. When [limit] is set, at most that many
  /// entries are purged. Returns the number of entries removed.
  Future<int> purgeDeadLetters(String queue, {DateTime? since, int? limit});
}

/// Logical task status across enqueue, running, success, failure states.
enum TaskState { queued, running, succeeded, failed, retried, cancelled }

/// Canonical task record stored in the result backend.
class TaskStatus {
  TaskStatus({
    required this.id,
    required this.state,
    this.payload,
    this.error,
    Map<String, Object?>? meta,
    required this.attempt,
    DateTime? updatedAt,
  }) : meta = Map.unmodifiable(meta ?? const {}),
       updatedAt = updatedAt ?? DateTime.now();

  /// The unique identifier for this task status.
  final String id;

  /// The current state of this task.
  final TaskState state;

  /// The payload associated with this task, if any.
  final Object? payload;

  /// The error that occurred during task execution, if any.
  final TaskError? error;

  /// Additional metadata for this task status.
  final Map<String, Object?> meta;

  /// The attempt number for this task execution.
  final int attempt;

  /// The timestamp when this status was last updated.
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'state': state.name,
    'payload': payload,
    'error': error?.toJson(),
    'meta': meta,
    'attempt': attempt,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TaskStatus.fromJson(Map<String, Object?> json) {
    return TaskStatus(
      id: json['id'] as String,
      state: TaskState.values.firstWhere(
        (value) => value.name == json['state'],
        orElse: () => TaskState.queued,
      ),
      payload: json['payload'],
      error: json['error'] != null
          ? TaskError.fromJson((json['error'] as Map).cast<String, Object?>())
          : null,
      meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
      attempt: (json['attempt'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }
}

/// Error metadata captured for failures.
class TaskError {
  const TaskError({
    required this.type,
    required this.message,
    this.stack,
    this.retryable = false,
    this.meta = const {},
  });

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

  Map<String, Object?> toJson() => {
    'type': type,
    'message': message,
    'stack': stack,
    'retryable': retryable,
    'meta': meta,
  };

  factory TaskError.fromJson(Map<String, Object?> json) {
    return TaskError(
      type: json['type'] as String? ?? 'Unknown',
      message: json['message'] as String? ?? '',
      stack: json['stack'] as String?,
      retryable: json['retryable'] as bool? ?? false,
      meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }
}

/// Dead letter queue entry containing the failed [envelope] and metadata.
class DeadLetterEntry {
  DeadLetterEntry({
    required this.envelope,
    this.reason,
    Map<String, Object?>? meta,
    required this.deadAt,
  }) : meta = Map.unmodifiable(meta ?? const {});

  /// Envelope that failed processing.
  final Envelope envelope;

  /// Optional reason describing the failure.
  final String? reason;

  /// Additional metadata captured at failure time.
  final Map<String, Object?> meta;

  /// Timestamp when the task was dead-lettered.
  final DateTime deadAt;

  Map<String, Object?> toJson() => {
    'envelope': envelope.toJson(),
    'reason': reason,
    'meta': meta,
    'deadAt': deadAt.toIso8601String(),
  };

  factory DeadLetterEntry.fromJson(Map<String, Object?> json) {
    return DeadLetterEntry(
      envelope: Envelope.fromJson(
        (json['envelope'] as Map).cast<String, Object?>(),
      ),
      reason: json['reason'] as String?,
      meta: (json['meta'] as Map?)?.cast<String, Object?>(),
      deadAt: DateTime.parse(json['deadAt'] as String),
    );
  }
}

/// Page of dead letter results with optional continuation offset.
class DeadLetterPage {
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
  const DeadLetterReplayResult({required this.entries, required this.dryRun});

  /// Entries that matched the replay filters.
  final List<DeadLetterEntry> entries;

  /// Whether this invocation was a dry run (no mutations performed).
  final bool dryRun;

  /// Number of entries touched.
  int get count => entries.length;
}

/// Result backend describes how task states are persisted and retrieved.
abstract class ResultBackend {
  /// Sets the status for the task with the given [taskId].
  ///
  /// Updates the [state], [payload], [error], [attempt], [meta], and sets a [ttl] if provided.
  Future<void> set(
    String taskId,
    TaskState state, {
    Object? payload,
    TaskError? error,
    int attempt,
    Map<String, Object?> meta,
    Duration? ttl,
  });

  /// Retrieves the [TaskStatus] for the task with the given [taskId], or null if not found.
  Future<TaskStatus?> get(String taskId);

  /// Returns a stream of [TaskStatus] updates for the task with the given [taskId].
  Stream<TaskStatus> watch(String taskId);

  /// Initializes a group with the given [descriptor].
  Future<void> initGroup(GroupDescriptor descriptor);

  /// Adds the [status] to the group with the given [groupId] and returns the updated [GroupStatus].
  Future<GroupStatus?> addGroupResult(String groupId, TaskStatus status);

  /// Retrieves the [GroupStatus] for the group with the given [groupId], or null if not found.
  Future<GroupStatus?> getGroup(String groupId);

  /// Updates the expiration for the given [taskId].
  Future<void> expire(String taskId, Duration ttl);
}

/// Schedule entry persisted by a Beat-like scheduler.
class ScheduleEntry {
  ScheduleEntry({
    required this.id,
    required this.taskName,
    required this.queue,
    required this.spec,
    this.args = const {},
    this.enabled = true,
    this.jitter,
    this.lastRunAt,
    Map<String, Object?>? meta,
  }) : meta = Map.unmodifiable(meta ?? const {});

  /// The unique identifier for this schedule entry.
  final String id;

  /// The name of the task to be scheduled.
  final String taskName;

  /// The queue to which the task should be sent.
  final String queue;

  /// The schedule specification (e.g., cron expression).
  final String spec;

  /// Arguments to pass to the task.
  final Map<String, Object?> args;

  /// Whether this schedule entry is enabled.
  final bool enabled;

  /// Optional jitter to add randomness to the schedule.
  final Duration? jitter;

  /// The timestamp of the last run, if any.
  final DateTime? lastRunAt;

  /// Additional metadata for this schedule entry.
  final Map<String, Object?> meta;

  ScheduleEntry copyWith({
    String? id,
    String? taskName,
    String? queue,
    String? spec,
    Map<String, Object?>? args,
    bool? enabled,
    Duration? jitter,
    DateTime? lastRunAt,
    Map<String, Object?>? meta,
  }) {
    return ScheduleEntry(
      id: id ?? this.id,
      taskName: taskName ?? this.taskName,
      queue: queue ?? this.queue,
      spec: spec ?? this.spec,
      args: args ?? this.args,
      enabled: enabled ?? this.enabled,
      jitter: jitter ?? this.jitter,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      meta: meta ?? this.meta,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'taskName': taskName,
    'queue': queue,
    'spec': spec,
    'args': args,
    'enabled': enabled,
    'jitterMs': jitter?.inMilliseconds,
    'lastRunAt': lastRunAt?.toIso8601String(),
    'meta': meta,
  };

  factory ScheduleEntry.fromJson(Map<String, Object?> json) {
    return ScheduleEntry(
      id: json['id'] as String,
      taskName: json['taskName'] as String,
      queue: json['queue'] as String,
      spec: json['spec'] as String,
      args: (json['args'] as Map?)?.cast<String, Object?>() ?? const {},
      enabled: json['enabled'] as bool? ?? true,
      jitter: json['jitterMs'] != null
          ? Duration(milliseconds: (json['jitterMs'] as num).toInt())
          : null,
      lastRunAt: json['lastRunAt'] != null
          ? DateTime.parse(json['lastRunAt'] as String)
          : null,
      meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }
}

/// Storage abstraction used by the scheduler to fetch due entries.
abstract class ScheduleStore {
  /// Returns a list of [ScheduleEntry] instances that are due at the given [now] time, limited to [limit].
  Future<List<ScheduleEntry>> due(DateTime now, {int limit = 100});

  /// Inserts or updates the [entry] in the store.
  Future<void> upsert(ScheduleEntry entry);

  /// Removes the schedule entry with the given [id] from the store.
  Future<void> remove(String id);
}

/// Configuration options attached to task handlers.
class TaskOptions {
  const TaskOptions({
    this.queue = 'default',
    this.maxRetries = 0,
    this.softTimeLimit,
    this.hardTimeLimit,
    this.rateLimit,
    this.unique = false,
    this.uniqueFor,
    this.priority = 0,
    this.acksLate = true,
    this.visibilityTimeout,
  });

  /// The queue to which tasks with these options should be sent.
  final String queue;

  /// The maximum number of retries for tasks with these options.
  final int maxRetries;

  /// The soft time limit for task execution.
  final Duration? softTimeLimit;

  /// The hard time limit for task execution.
  final Duration? hardTimeLimit;

  /// The rate limit for tasks with these options.
  final String? rateLimit;

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
}

/// Context passed to handler implementations during execution.
class TaskContext {
  TaskContext({
    required this.id,
    required this.attempt,
    required this.headers,
    required this.meta,
    required this.heartbeat,
    required this.extendLease,
    required this.progress,
  });

  /// The unique identifier of the task.
  final String id;

  /// The current attempt number.
  final int attempt;

  /// Headers associated with the task.
  final Map<String, String> headers;

  /// Metadata for the task.
  final Map<String, Object?> meta;

  /// Function to send a heartbeat.
  final void Function() heartbeat;

  /// Function to extend the lease by a given duration.
  final Future<void> Function(Duration) extendLease;

  /// Function to report progress.
  final Future<void> Function(
    double percentComplete, {
    Map<String, Object?>? data,
  })
  progress;
}

/// Runtime task handler.
abstract class TaskHandler<R> {
  /// The name of this task handler.
  String get name;

  /// The options for this task handler.
  TaskOptions get options;

  /// Executes the task with the given [context] and [args].
  Future<R> call(TaskContext context, Map<String, Object?> args);

  /// Optional entrypoint that allows this task to execute inside an isolate
  /// worker. When `null`, the handler runs in the coordinator isolate.
  TaskEntrypoint? get isolateEntrypoint => null;
}

/// Registry mapping task names to handler implementations.
abstract class TaskRegistry {
  /// Registers the [handler] with this registry.
  void register(TaskHandler handler);

  /// Resolves the handler for the given [name], or null if not found.
  TaskHandler? resolve(String name);
}

/// Default in-memory registry implementation.
class SimpleTaskRegistry implements TaskRegistry {
  final Map<String, TaskHandler> _handlers = {};

  @override
  /// Registers the [handler] in this registry.
  void register(TaskHandler handler) {
    _handlers[handler.name] = handler;
  }

  @override
  /// Resolves the handler for the given [name], or returns null if not found.
  TaskHandler? resolve(String name) => _handlers[name];
}

/// Retry strategy used to compute the next backoff delay.
abstract class RetryStrategy {
  /// Computes the next delay duration for the given [attempt], [error], and [stackTrace].
  Duration nextDelay(int attempt, Object error, StackTrace stackTrace);
}

/// Optional rate limiter interface shared across workers.
abstract class RateLimiter {
  /// Attempts to acquire [tokens] for the given [key], with optional [interval] and [meta].
  Future<RateLimitDecision> acquire(
    String key, {
    int tokens = 1,
    Duration? interval,
    Map<String, Object?>? meta,
  });
}

/// Result of attempting to acquire tokens from the rate limiter.
class RateLimitDecision {
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
abstract class LockStore {
  /// Attempts to acquire a lock for the given [key], with [ttl] and optional [owner].
  Future<Lock?> acquire(
    String key, {
    Duration ttl = const Duration(seconds: 30),
    String? owner,
  });
}

abstract class Lock {
  /// The key of this lock.
  String get key;

  /// Renews this lock with a new [ttl], returning whether successful.
  Future<bool> renew(Duration ttl);

  /// Releases this lock.
  Future<void> release();
}

/// Middleware hook invoked for lifecycle events around enqueue/consume/execute.
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

  /// The number of completed results.
  int get completed => results.length;

  /// Whether the group is complete.
  bool get isComplete => completed >= expected;
}
