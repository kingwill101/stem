import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:stem/stem.dart';

import 'demo_config.dart';

/// Small scalar-only work, executed through the normal task isolate.
final routingProbe = TaskDefinition<Map<String, Object?>, Map<String, Object?>>(
  name: routingProbeTaskName,
  encodeArgs: (args) => args,
  decodeResult: (value) => Map<String, Object?>.from(value! as Map),
  defaultOptions: const TaskOptions(queue: routingQueueName),
);

final routingProbeHandler = FunctionTaskHandler<Map<String, Object?>>(
  name: routingProbe.name,
  entrypoint: _routingProbeTask,
  options: routingProbe.defaultOptions,
);

Future<Object?> _routingProbeTask(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final batch = args['probeBatchId'];
  final index = args['index'];
  if (batch is! String ||
      batch.length > 100 ||
      index is! int ||
      index < 0 ||
      index >= 6) {
    throw ArgumentError('Invalid routing probe');
  }
  List<int> bytes = utf8.encode('$batch:$index');
  for (var round = 0; round < 128; round++) {
    bytes = sha256.convert(bytes).bytes;
  }
  return {
    'probeBatchId': batch,
    'index': index,
    'checksum': bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(),
  };
}

/// A failure after earlier commits reports those IDs so the host can still
/// request a wakeup for saved work without republishing the batch.
class RoutingProbePublicationFailure implements Exception {
  RoutingProbePublicationFailure(
    this.committedIds,
    this.cause,
    this.stackTrace,
  );
  final List<String> committedIds;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() =>
      '${committedIds.length} probes saved before failure: $cause';
}

/// Publish at most six probes; worker identity comes from TaskStatus.meta.
Future<List<String>> enqueueRoutingProbes(
  StemApp app, {
  required String queue,
  int count = 6,
}) async {
  if (queue != queueName && queue != routingQueueName) {
    throw ArgumentError.value(queue, 'queue', 'Not a demo task queue');
  }
  if (count < 1 || count > 6) {
    throw RangeError.range(count, 1, 6, 'count');
  }
  final random = Random.secure();
  final batch = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final ids = <String>[];
  try {
    for (var index = 0; index < count; index++) {
      ids.add(
        await app.enqueueCall(
          routingProbe.buildCall(
            {'probeBatchId': batch, 'index': index},
            meta: {'probeBatchId': batch, 'index': index},
            enqueueOptions: TaskEnqueueOptions(queue: queue),
          ),
        ),
      );
    }
  } catch (error, stack) {
    if (ids.isEmpty) rethrow;
    throw RoutingProbePublicationFailure(List.unmodifiable(ids), error, stack);
  }
  return ids;
}
