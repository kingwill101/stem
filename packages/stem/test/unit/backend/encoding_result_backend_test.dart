import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('EncodingResultBackend', () {
    test('encodes and decodes task payloads', () async {
      final inner = InMemoryResultBackend();
      const encoder = _PrefixTaskPayloadEncoder();
      final registry = TaskPayloadEncoderRegistry(
        defaultResultEncoder: encoder,
        defaultArgsEncoder: const JsonTaskPayloadEncoder(),
      );
      final backend = withTaskPayloadEncoder(inner, registry);

      const taskId = 'task-encode';
      final meta = {stemResultEncoderMetaKey: encoder.id};
      await backend.set(
        taskId,
        TaskState.succeeded,
        payload: 'hello',
        attempt: 0,
        meta: meta,
      );

      final status = await backend.get(taskId);
      expect(status, isNotNull);
      expect(status!.payload, 'hello');
    });

    test('decodes watch streams and group results', () async {
      final inner = InMemoryResultBackend();
      const encoder = _PrefixTaskPayloadEncoder();
      final registry = TaskPayloadEncoderRegistry(
        defaultResultEncoder: encoder,
        defaultArgsEncoder: const JsonTaskPayloadEncoder(),
      );
      final backend = withTaskPayloadEncoder(inner, registry);

      const taskId = 'watched-task';

      final events = <TaskStatus>[];
      final sub = backend.watch(taskId).listen(events.add);

      final meta = {stemResultEncoderMetaKey: encoder.id};
      await backend.set(
        taskId,
        TaskState.succeeded,
        payload: 'world',
        attempt: 0,
        meta: meta,
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      expect(events, isNotEmpty);
      expect(events.first.payload, 'world');

      await backend.initGroup(GroupDescriptor(id: 'grp', expected: 1));
      final groupStatus = TaskStatus(
        id: 'grp-task',
        state: TaskState.succeeded,
        payload: 'group-value',
        attempt: 0,
        meta: meta,
      );
      final updated = await backend.addGroupResult('grp', groupStatus);
      expect(updated, isNotNull);
      expect(updated!.results['grp-task']?.payload, 'group-value');

      final fetched = await backend.getGroup('grp');
      expect(fetched?.results['grp-task']?.payload, 'group-value');
    });
  });
}

class _PrefixTaskPayloadEncoder extends TaskPayloadEncoder {
  const _PrefixTaskPayloadEncoder();

  @override
  Object? encode(Object? value) {
    if (value is String) {
      return 'ENC:$value';
    }
    return value;
  }

  @override
  Object? decode(Object? stored) {
    if (stored is String && stored.startsWith('ENC:')) {
      return stored.substring(4);
    }
    return stored;
  }
}
