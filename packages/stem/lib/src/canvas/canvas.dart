import 'dart:async';
import 'dart:math';

import '../backend/encoding_result_backend.dart';
import '../core/chord_metadata.dart';
import '../core/contracts.dart';
import '../core/encoder_keys.dart';
import '../core/envelope.dart';
import '../core/task_result.dart';
import '../core/task_payload_encoder.dart';

/// Describes a task to schedule along with optional decoder metadata.
class TaskSignature<T extends Object?> {
  const TaskSignature._({
    required this.name,
    required Envelope Function() builder,
    this.decode,
  }) : _builder = builder;

  /// Logical task name.
  final String name;

  final Envelope Function() _builder;

  /// Optional decoder that transforms backend payloads into typed values.
  final T Function(Object? payload)? decode;

  /// Builds an [Envelope] for this task.
  Envelope call() => _builder();

  /// Decodes [payload] if a decoder is configured, otherwise performs a simple
  /// cast. Returns `null` when [payload] is `null`.
  T? decodePayload(Object? payload) {
    if (payload == null) return null;
    if (decode != null) {
      return decode!(payload);
    }
    return payload as T?;
  }

  /// Creates a signature from a custom envelope builder.
  factory TaskSignature.custom(
    String name,
    Envelope Function() builder, {
    T Function(Object? payload)? decode,
  }) => TaskSignature._(name: name, builder: builder, decode: decode);
}

/// Returns a [TaskSignature] that creates an [Envelope] for a task.
///
/// The envelope is configured with [name], [args], [headers], and [options].
/// Values from [options] populate queueing behavior such as [TaskOptions.queue],
/// [TaskOptions.priority], [TaskOptions.maxRetries], and
/// [TaskOptions.visibilityTimeout].
TaskSignature<T> task<T extends Object?>(
  String name, {
  Map<String, Object?> args = const {},
  Map<String, String> headers = const {},
  TaskOptions options = const TaskOptions(),
  Map<String, Object?> meta = const {},
  DateTime? notBefore,
  T Function(Object? payload)? decode,
}) => TaskSignature._(
  name: name,
  decode: decode,
  builder: () => Envelope(
    name: name,
    args: args,
    headers: headers,
    queue: options.queue,
    priority: options.priority,
    maxRetries: options.maxRetries,
    visibilityTimeout: options.visibilityTimeout,
    meta: meta,
    notBefore: notBefore,
  ),
);

/// Result returned by [Canvas.chain].
class TaskChainResult<T extends Object?> {
  const TaskChainResult({
    required this.chainId,
    required this.finalTaskId,
    this.finalStatus,
    this.value,
  });

  final String chainId;
  final String finalTaskId;
  final TaskStatus? finalStatus;
  final T? value;

  bool get isCompleted => finalStatus?.state == TaskState.succeeded;
}

/// Handle returned by [Canvas.group] providing a stream of typed results.
class GroupDispatch<T extends Object?> {
  GroupDispatch({
    required this.groupId,
    required this.taskIds,
    required this.results,
    Future<void> Function()? onDispose,
  }) : _onDispose = onDispose;

  final String groupId;
  final List<String> taskIds;
  final Stream<TaskResult<T>> results;
  final Future<void> Function()? _onDispose;

  Future<void> dispose() async {
    final onDispose = _onDispose;
    if (onDispose != null) {
      await onDispose();
    }
  }
}

/// Result returned by [Canvas.chord].
class ChordResult<T extends Object?> {
  const ChordResult({
    required this.chordId,
    required this.callbackTaskId,
    required this.values,
  });

  final String chordId;
  final String callbackTaskId;
  final List<T?> values;
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
    required ResultBackend backend,
    required this.registry,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
    Random? random,
  }) : payloadEncoders = ensureTaskPayloadEncoderRegistry(
         encoderRegistry,
         resultEncoder: resultEncoder,
         argsEncoder: argsEncoder,
         additionalEncoders: additionalEncoders,
       ),
       _random = random ?? Random() {
    this.backend = withTaskPayloadEncoder(backend, payloadEncoders);
  }

  /// The message broker used to publish task envelopes.
  final Broker broker;

  final TaskPayloadEncoderRegistry payloadEncoders;

  /// The result backend used to record task states and group progress.
  late final ResultBackend backend;

  /// The task registry for resolving task metadata and handlers.
  final TaskRegistry registry;

  /// Source of randomness for ID generation.
  final Random _random;

  /// Publishes a single task described by [signature].
  ///
  /// The task is published to its configured queue and recorded as
  /// [TaskState.queued] in [backend]. Returns the task id.
  Future<String> send(TaskSignature signature) async {
    final (envelope, resultEncoder) = _prepareEnvelope(signature());
    await broker.publish(envelope);
    final queuedMeta = _withResultEncoderMeta({
      ...envelope.meta,
      'queue': envelope.queue,
    }, resultEncoder);
    await backend.set(
      envelope.id,
      TaskState.queued,
      attempt: envelope.attempt,
      meta: queuedMeta,
    );
    return envelope.id;
  }

  /// Publishes multiple tasks as a group and streams typed completions.
  ///
  /// Initializes a group in [backend], publishes each signature, and tags
  /// headers/meta so workers know the run belongs to the group. The returned
  /// [GroupDispatch] exposes task ids and a `Stream<TaskResult<T>>` that emits
  /// each completion with the decoded payload.
  Future<GroupDispatch<T>> group<T extends Object?>(
    List<TaskSignature<T>> signatures, {
    String? groupId,
  }) async {
    final id = groupId ?? _generateId('grp');
    if (groupId == null) {
      await backend.initGroup(
        GroupDescriptor(id: id, expected: signatures.length),
      );
    }
    final taskIds = <String>[];
    for (final signature in signatures) {
      final raw = signature();
      final grouped = raw.copyWith(
        headers: {...raw.headers, 'stem-group-id': id},
        meta: {...raw.meta, 'groupId': id},
      );
      final (envelope, resultEncoder) = _prepareEnvelope(grouped);
      taskIds.add(envelope.id);
      await broker.publish(envelope);
      final queuedMeta = _withResultEncoderMeta({
        ...envelope.meta,
        'queue': envelope.queue,
        'groupId': id,
      }, resultEncoder);
      await backend.set(
        envelope.id,
        TaskState.queued,
        attempt: envelope.attempt,
        meta: queuedMeta,
      );
    }

    final controller = StreamController<TaskResult<T>>.broadcast();
    if (taskIds.isEmpty) {
      scheduleMicrotask(() => controller.close());
      return GroupDispatch(
        groupId: id,
        taskIds: taskIds,
        results: controller.stream,
        onDispose: () async => controller.close(),
      );
    }

    final remaining = taskIds.toSet();
    final subscriptions = <StreamSubscription<TaskStatus>>[];
    var closed = false;

    Future<void> closeController() async {
      if (closed) return;
      closed = true;
      await controller.close();
    }

    for (var i = 0; i < taskIds.length; i++) {
      final taskId = taskIds[i];
      final signature = signatures[i];
      late StreamSubscription<TaskStatus> sub;
      sub = backend.watch(taskId).listen((status) async {
        if (!status.state.isTerminal) {
          return;
        }
        await sub.cancel();
        final value = status.state == TaskState.succeeded
            ? signature.decodePayload(status.payload)
            : null;
        if (!controller.isClosed) {
          controller.add(
            TaskResult<T>(
              taskId: taskId,
              status: status,
              value: value,
              rawPayload: status.payload,
            ),
          );
        }
        remaining.remove(taskId);
        if (remaining.isEmpty) {
          await closeController();
        }
      }, onError: controller.addError);
      subscriptions.add(sub);
    }

    Future<void> dispose() async {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      await closeController();
    }

    controller.onCancel = dispose;

    return GroupDispatch<T>(
      groupId: id,
      taskIds: taskIds,
      results: controller.stream,
      onDispose: dispose,
    );
  }

  /// Runs tasks sequentially, passing each result to the next.
  ///
  /// Each task is published only after the previous task succeeds. The result
  /// of a step is provided to the next via `chainPrevResult` in meta. The
  /// returned [TaskChainResult] provides the final task id, status, and typed
  /// value when available.
  ///
  /// Throws an [ArgumentError] if [signatures] is empty.
  Future<TaskChainResult<T>> chain<T extends Object?>(
    List<TaskSignature<T>> signatures, {
    void Function(int index, TaskStatus status, T? value)? onStepCompleted,
  }) async {
    if (signatures.isEmpty) {
      throw ArgumentError('Chain requires at least one task');
    }
    final chainId = _generateId('chain');
    final completer = Completer<TaskChainResult<T>>();

    Future<void> runStep(int index, Object? previousResult) async {
      final signature = signatures[index];
      final raw = signature();
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
      final (preparedEnvelope, resultEncoder) = _prepareEnvelope(envelope);

      late StreamSubscription<TaskStatus> sub;
      sub = backend
          .watch(preparedEnvelope.id)
          .listen(
            (status) async {
              if (status.state == TaskState.succeeded) {
                final decoded = signature.decodePayload(status.payload);
                onStepCompleted?.call(index, status, decoded);
                await sub.cancel();
                if (index + 1 < signatures.length) {
                  await runStep(index + 1, status.payload);
                } else if (!completer.isCompleted) {
                  completer.complete(
                    TaskChainResult<T>(
                      chainId: chainId,
                      finalTaskId: preparedEnvelope.id,
                      finalStatus: status,
                      value: decoded,
                    ),
                  );
                }
              } else if (status.state == TaskState.failed ||
                  status.state == TaskState.cancelled) {
                await sub.cancel();
                if (!completer.isCompleted) {
                  completer.completeError(
                    StateError('Chain $chainId failed at step $index'),
                  );
                }
              }
            },
            onError: (error, stack) {
              if (!completer.isCompleted) {
                completer.completeError(error, stack);
              }
            },
          );

      await broker.publish(preparedEnvelope);
      final queuedMeta = _withResultEncoderMeta(
        preparedEnvelope.meta,
        resultEncoder,
      );
      await backend.set(
        preparedEnvelope.id,
        TaskState.queued,
        attempt: preparedEnvelope.attempt,
        meta: queuedMeta,
      );
    }

    unawaited(runStep(0, null));
    return completer.future;
  }

  /// Coordinates a chord: a group of tasks followed by a callback.
  ///
  /// Publishes [body] as a group and waits until every task in the group
  /// succeeds. Then publishes [callback] with all group results in its meta
  /// as `chordResults`. Completes with a [ChordResult] containing the callback
  /// task id and the typed results emitted by the body.
  ///
  /// Throws an [ArgumentError] if [body] is empty.
  Future<ChordResult<T>> chord<T extends Object?>({
    required List<TaskSignature<T>> body,
    required TaskSignature callback,
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    final handle = await _startChord<T>(body: body, callback: callback);
    final values = await _awaitChordValues(
      handle.chordId,
      body,
      handle.bodyTaskIds,
      pollInterval,
    );
    final callbackTaskId = await handle.callbackFuture;
    return ChordResult<T>(
      chordId: handle.chordId,
      callbackTaskId: callbackTaskId,
      values: values,
    );
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

  Future<_ChordHandle> _startChord<T extends Object?>({
    required List<TaskSignature<T>> body,
    required TaskSignature callback,
  }) async {
    if (body.isEmpty) {
      throw ArgumentError('Chord body must have at least one task');
    }
    final chordId = _generateId('chord');
    var callbackEnvelope = callback();
    final (encodedCallback, _) = _prepareEnvelope(callbackEnvelope);
    callbackEnvelope = encodedCallback;
    await backend.initGroup(
      GroupDescriptor(
        id: chordId,
        expected: body.length,
        meta: {ChordMetadata.callbackEnvelope: callbackEnvelope.toJson()},
      ),
    );
    final bodyDispatch = await group(body, groupId: chordId);
    final bodyTaskIds = bodyDispatch.taskIds;
    await bodyDispatch.dispose();
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
    return _ChordHandle(
      chordId: chordId,
      bodyTaskIds: bodyTaskIds,
      callbackFuture: completer.future,
    );
  }

  Future<List<T?>> _awaitChordValues<T extends Object?>(
    String chordId,
    List<TaskSignature<T>> body,
    List<String> taskIds,
    Duration pollInterval,
  ) async {
    while (true) {
      final status = await backend.getGroup(chordId);
      if (status == null || !status.isComplete) {
        await Future<void>.delayed(pollInterval);
        continue;
      }
      final failures = status.results.entries
          .where(
            (entry) =>
                entry.value.state == TaskState.failed ||
                entry.value.state == TaskState.cancelled,
          )
          .toList();
      if (failures.isNotEmpty) {
        throw StateError(
          'Chord $chordId failed due to task ${failures.first.key}',
        );
      }
      final values = <T?>[];
      for (var i = 0; i < taskIds.length; i++) {
        final taskId = taskIds[i];
        final taskStatus = status.results[taskId];
        if (taskStatus == null) {
          throw StateError('Missing status for task $taskId in chord $chordId');
        }
        values.add(body[i].decodePayload(taskStatus.payload));
      }
      return values;
    }
  }

  (Envelope, TaskPayloadEncoder) _prepareEnvelope(Envelope envelope) {
    final handler = registry.resolve(envelope.name);
    final argsEncoder = _resolveArgsEncoder(handler);
    final resultEncoder = _resolveResultEncoder(handler);
    final encodedArgs = _encodeArgs(envelope.args, argsEncoder);
    final encodedHeaders = _withArgsEncoderHeader(
      envelope.headers,
      argsEncoder,
    );
    final encodedMeta = _withArgsEncoderMeta(envelope.meta, argsEncoder);
    final encodedEnvelope = envelope.copyWith(
      args: encodedArgs,
      headers: encodedHeaders,
      meta: encodedMeta,
    );
    return (encodedEnvelope, resultEncoder);
  }

  TaskPayloadEncoder _resolveArgsEncoder(TaskHandler? handler) {
    final encoder = handler?.metadata.argsEncoder;
    payloadEncoders.register(encoder);
    return encoder ?? payloadEncoders.defaultArgsEncoder;
  }

  TaskPayloadEncoder _resolveResultEncoder(TaskHandler? handler) {
    final encoder = handler?.metadata.resultEncoder;
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
      'Task args encoder ${encoder.id} must return Map<String, Object?> values, got ${encoded.runtimeType}.',
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
}

class _ChordHandle {
  const _ChordHandle({
    required this.chordId,
    required this.bodyTaskIds,
    required this.callbackFuture,
  });

  final String chordId;
  final List<String> bodyTaskIds;
  final Future<String> callbackFuture;
}

extension TaskDefinitionCanvasX<TArgs, TResult extends Object?>
    on TaskDefinition<TArgs, TResult> {
  TaskSignature<TResult> toSignature(
    TArgs args, {
    Map<String, String> headers = const {},
    TaskOptions? options,
    DateTime? notBefore,
    Map<String, Object?>? meta,
    TResult Function(Object? payload)? decode,
  }) {
    final call = this.call(
      args,
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
    );
    return task<TResult>(
      name,
      args: call.encodeArgs(),
      headers: call.headers,
      options: call.resolveOptions(),
      meta: call.meta,
      notBefore: call.notBefore,
      decode: decode ?? decodeResult,
    );
  }
}
