import 'dart:async';
import 'dart:math';

import '../core/contracts.dart';
import '../core/envelope.dart';
import '../core/chord_metadata.dart';

/// A function that builds an [Envelope] describing a task to schedule.
typedef TaskSignature = Envelope Function();

/// Returns a [TaskSignature] that creates an [Envelope] for a task.
///
/// The envelope is configured with [name], [args], [headers], and [options].
/// Values from [options] populate queueing behavior such as [TaskOptions.queue],
/// [TaskOptions.priority], [TaskOptions.maxRetries], and
/// [TaskOptions.visibilityTimeout].
TaskSignature task(
  String name, {
  Map<String, Object?> args = const {},
  Map<String, String> headers = const {},
  TaskOptions options = const TaskOptions(),
}) {
  return () => Envelope(
    name: name,
    args: args,
    headers: headers,
    queue: options.queue,
    priority: options.priority,
    maxRetries: options.maxRetries,
    visibilityTimeout: options.visibilityTimeout,
  );
}

/// A high-level API for composing and dispatching tasks.
///
/// [Canvas] publishes [Envelope]s to a [Broker] and records status in a
/// [ResultBackend]. It provides helpers to send a single task, fan-out a
/// group, run a sequential chain, and coordinate a chord (group with
/// callback).
class Canvas {
  /// Creates a [Canvas] that uses [broker] to publish messages and [backend]
  /// to persist task state and group metadata.
  ///
  /// [registry] provides task lookups when needed. A custom [random] can be
  /// supplied to influence ID generation in tests.
  Canvas({
    required this.broker,
    required this.backend,
    required this.registry,
    Random? random,
  }) : _random = random ?? Random();

  /// The message broker used to publish task envelopes.
  final Broker broker;

  /// The result backend used to record task states and group progress.
  final ResultBackend backend;

  /// The task registry for resolving task metadata and handlers.
  final TaskRegistry registry;

  /// Source of randomness for ID generation.
  final Random _random;

  /// Publishes a single task described by [signature].
  ///
  /// The task is published to its configured queue and recorded as
  /// [TaskState.queued] in [backend]. Returns the task id.
  Future<String> send(TaskSignature signature) async {
    final envelope = signature();
    await broker.publish(envelope);
    await backend.set(
      envelope.id,
      TaskState.queued,
      attempt: envelope.attempt,
      meta: {'queue': envelope.queue},
    );
    return envelope.id;
  }

  /// Publishes multiple tasks as a group.
  ///
  /// Initializes a group in [backend] and publishes each [signatures] entry,
  /// tagging their headers with `stem-group-id` and meta with `groupId`.
  /// If [groupId] is not provided, a unique id is generated.
  /// Returns the list of task ids.
  Future<List<String>> group(
    List<TaskSignature> signatures, {
    String? groupId,
  }) async {
    final id = groupId ?? _generateId('grp');
    if (groupId == null) {
      await backend.initGroup(
        GroupDescriptor(id: id, expected: signatures.length),
      );
    }
    final ids = <String>[];
    for (final signature in signatures) {
      final raw = signature();
      final envelope = raw.copyWith(
        headers: {...raw.headers, 'stem-group-id': id},
        meta: {...raw.meta, 'groupId': id},
      );
      ids.add(envelope.id);
      await broker.publish(envelope);
      await backend.set(
        envelope.id,
        TaskState.queued,
        attempt: envelope.attempt,
        meta: {...envelope.meta, 'queue': envelope.queue, 'groupId': id},
      );
    }
    return ids;
  }

  /// Runs tasks sequentially, passing each result to the next.
  ///
  /// Each task is published only after the previous task succeeds. The result
  /// of a step is provided to the next via `chainPrevResult` in meta.
  /// Completes with the id of the final task when the chain succeeds, and
  /// completes with an error if any step fails.
  ///
  /// Throws an [ArgumentError] if [signatures] is empty.
  Future<String> chain(List<TaskSignature> signatures) async {
    if (signatures.isEmpty) {
      throw ArgumentError('Chain requires at least one task');
    }
    final chainId = _generateId('chain');
    final completer = Completer<String>();

    Future<void> runStep(int index, Object? previousResult) async {
      final raw = signatures[index]();
      final meta = {
        ...raw.meta,
        'chainId': chainId,
        'chainIndex': index,
        'queue': raw.queue,
        if (previousResult != null) 'chainPrevResult': previousResult,
      };
      final headers = {
        ...raw.headers,
        'stem-chain-id': chainId,
        'stem-chain-index': '$index',
      };
      final envelope = raw.copyWith(headers: headers, meta: meta);

      final stream = backend.watch(envelope.id);
      late StreamSubscription<TaskStatus> sub;
      sub = stream.listen((status) async {
        if (status.state == TaskState.succeeded) {
          await sub.cancel();
          if (index + 1 < signatures.length) {
            await runStep(index + 1, status.payload);
          } else if (!completer.isCompleted) {
            completer.complete(envelope.id);
          }
        } else if (status.state == TaskState.failed ||
            status.state == TaskState.cancelled) {
          await sub.cancel();
          if (!completer.isCompleted) {
            completer.completeError('Chain $chainId failed at step $index');
          }
        }
      });

      await broker.publish(envelope);
      await backend.set(
        envelope.id,
        TaskState.queued,
        attempt: envelope.attempt,
        meta: meta,
      );
    }

    unawaited(runStep(0, null));
    return completer.future;
  }

  /// Coordinates a chord: a group of tasks followed by a callback.
  ///
  /// Publishes [body] as a group and waits until every task in the group
  /// succeeds. Then publishes [callback] with all group results in its meta
  /// as `chordResults`. Completes with the callback task id, or completes
  /// with an error if any body task fails.
  ///
  /// Throws an [ArgumentError] if [body] is empty.
  Future<String> chord({
    required List<TaskSignature> body,
    required TaskSignature callback,
  }) async {
    if (body.isEmpty) {
      throw ArgumentError('Chord body must have at least one task');
    }
    final chordId = _generateId('chord');
    final callbackEnvelope = callback();
    await backend.initGroup(
      GroupDescriptor(
        id: chordId,
        expected: body.length,
        meta: {ChordMetadata.callbackEnvelope: callbackEnvelope.toJson()},
      ),
    );
    await group(body, groupId: chordId);

    final completer = Completer<String>();
    unawaited(
      _monitorChord(chordId, callbackEnvelope.id, completer).catchError((
        error,
        stack,
      ) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      }),
    );
    return completer.future;
  }

  /// Monitors [chordId] until the callback is enqueued or the body fails.
  Future<void> _monitorChord(
    String chordId,
    String callbackId,
    Completer<String> completer,
  ) async {
    while (true) {
      final status = await backend.getGroup(chordId);
      if (status == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      final hasFailure = status.results.values.any(
        (s) => s.state == TaskState.failed || s.state == TaskState.cancelled,
      );
      if (hasFailure) {
        if (!completer.isCompleted) {
          completer.completeError('Chord $chordId failed due to task failure');
        }
        return;
      }

      final callbackStatus = await backend.get(callbackId);
      if (callbackStatus != null) {
        if (!completer.isCompleted) {
          completer.complete(callbackId);
        }
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Generates a unique id using [prefix], current time, and randomness.
  String _generateId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
}
