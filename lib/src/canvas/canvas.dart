import 'dart:async';
import 'dart:math';

import '../core/contracts.dart';
import '../core/envelope.dart';

typedef TaskSignature = Envelope Function();

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

class Canvas {
  Canvas({
    required this.broker,
    required this.backend,
    required this.registry,
    Random? random,
  }) : _random = random ?? Random();

  final Broker broker;
  final ResultBackend backend;
  final TaskRegistry registry;
  final Random _random;

  Future<String> send(TaskSignature signature) async {
    final envelope = signature();
    await broker.publish(envelope, queue: envelope.queue);
    await backend.set(
      envelope.id,
      TaskState.queued,
      attempt: envelope.attempt,
      meta: {'queue': envelope.queue},
    );
    return envelope.id;
  }

  Future<List<String>> group(
    List<TaskSignature> signatures, {
    String? groupId,
  }) async {
    final id = groupId ?? _generateId('grp');
    await backend.initGroup(
      GroupDescriptor(id: id, expected: signatures.length),
    );
    final ids = <String>[];
    for (final signature in signatures) {
      final raw = signature();
      final envelope = raw.copyWith(
        headers: {...raw.headers, 'stem-group-id': id},
        meta: {...raw.meta, 'groupId': id},
      );
      ids.add(envelope.id);
      await broker.publish(envelope, queue: envelope.queue);
      await backend.set(
        envelope.id,
        TaskState.queued,
        attempt: envelope.attempt,
        meta: {...envelope.meta, 'queue': envelope.queue, 'groupId': id},
      );
    }
    return ids;
  }

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

      await broker.publish(envelope, queue: envelope.queue);
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

  Future<String> chord({
    required List<TaskSignature> body,
    required TaskSignature callback,
  }) async {
    if (body.isEmpty) {
      throw ArgumentError('Chord body must have at least one task');
    }
    final chordId = _generateId('chord');
    await backend.initGroup(
      GroupDescriptor(
        id: chordId,
        expected: body.length,
        meta: {'callback': callback().name},
      ),
    );
    await group(body, groupId: chordId);

    final completer = Completer<String>();
    unawaited(
      _monitorChord(chordId, callback, completer).catchError((error, stack) {
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      }),
    );
    return completer.future;
  }

  Future<void> _monitorChord(
    String chordId,
    TaskSignature callback,
    Completer<String> completer,
  ) async {
    while (true) {
      final status = await backend.getGroup(chordId);
      if (status == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      if (!status.isComplete) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      final allSucceeded = status.results.values.every(
        (s) => s.state == TaskState.succeeded,
      );
      if (!allSucceeded) {
        if (!completer.isCompleted) {
          completer.completeError('Chord $chordId failed due to task failure');
        }
        return;
      }
      final envelope = callback();
      final payload = status.results.values.map((s) => s.payload).toList();
      await broker.publish(
        envelope.copyWith(
          headers: {...envelope.headers, 'stem-chord-id': chordId},
          meta: {...envelope.meta, 'chordResults': payload},
        ),
        queue: envelope.queue,
      );
      await backend.set(
        envelope.id,
        TaskState.queued,
        attempt: envelope.attempt,
        meta: {
          ...envelope.meta,
          'queue': envelope.queue,
          'chordId': chordId,
          'chordResults': payload,
        },
      );
      if (!completer.isCompleted) {
        completer.complete(envelope.id);
      }
      break;
    }
  }

  String _generateId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
}
