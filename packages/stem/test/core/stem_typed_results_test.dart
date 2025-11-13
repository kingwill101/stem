import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('Stem.waitForTask', () {
    test('returns typed payload on success', () async {
      final app = await StemApp.inMemory(
        tasks: [
          FunctionTaskHandler<String>(
            name: 'typed.echo',
            entrypoint: (context, args) async => 'hello',
          ),
        ],
      );
      await app.start();
      try {
        final taskId = await app.stem.enqueue('typed.echo');
        final result = await app.stem.waitForTask<String>(taskId);
        expect(result, isNotNull);
        expect(result!.isSucceeded, isTrue);
        expect(result.value, 'hello');
        expect(result.status.state, TaskState.succeeded);
      } finally {
        await app.shutdown();
      }
    });

    test('skips decoder when task fails', () async {
      final app = await StemApp.inMemory(
        tasks: [
          FunctionTaskHandler<void>(
            name: 'typed.fail',
            entrypoint: (context, args) async => throw StateError('boom'),
          ),
        ],
      );
      await app.start();
      try {
        final taskId = await app.stem.enqueue('typed.fail');
        var decodeInvocations = 0;
        final result = await app.stem.waitForTask<String>(
          taskId,
          decode: (payload) {
            decodeInvocations += 1;
            return payload as String;
          },
        );
        expect(result, isNotNull);
        expect(result!.isFailed, isTrue);
        expect(result.value, isNull);
        expect(decodeInvocations, 0);
        expect(result.status.error?.message, contains('boom'));
      } finally {
        await app.shutdown();
      }
    });

    test('returns latest status when timeout elapses', () async {
      final app = await StemApp.inMemory(
        tasks: [
          FunctionTaskHandler<void>(
            name: 'typed.sleep',
            entrypoint: (context, args) async =>
                Future<void>.delayed(const Duration(milliseconds: 200)),
          ),
        ],
      );
      await app.start();
      try {
        final taskId = await app.stem.enqueue('typed.sleep');
        final timedOut = await app.stem.waitForTask<void>(
          taskId,
          timeout: const Duration(milliseconds: 20),
        );
        expect(timedOut, isNotNull);
        expect(timedOut!.timedOut, isTrue);
        expect(
          timedOut.status.state,
          anyOf(TaskState.queued, TaskState.running),
        );
        // Verify we can still await the final completion later.
        final completed = await app.stem.waitForTask<void>(taskId);
        expect(completed!.isSucceeded, isTrue);
      } finally {
        await app.shutdown();
      }
    });

    test('respects custom result encoder', () async {
      final app = await StemApp.inMemory(
        tasks: [
          FunctionTaskHandler<String>(
            name: 'typed.custom',
            entrypoint: (context, args) async => 'secret-text',
          ),
        ],
        resultEncoder: const _Base64TaskPayloadEncoder(),
      );
      await app.start();
      try {
        final taskId = await app.stem.enqueue('typed.custom');
        final result = await app.stem.waitForTask<String>(taskId);
        expect(result?.value, 'secret-text');
        expect(result?.status.payload, 'secret-text');
      } finally {
        await app.shutdown();
      }
    });

    test('encodes and decodes task arguments with global encoder', () async {
      final app = await StemApp.inMemory(
        tasks: [
          FunctionTaskHandler<String>(
            name: 'typed.args',
            entrypoint: (context, args) async {
              return args['secret'] as String;
            },
          ),
        ],
        argsEncoder: const _JsonArgsTaskPayloadEncoder(),
      );
      await app.start();
      try {
        final taskId = await app.stem.enqueue(
          'typed.args',
          args: const {'secret': 'encrypted-text'},
        );
        final result = await app.stem.waitForTask<String>(taskId);
        expect(result?.value, 'encrypted-text');
      } finally {
        await app.shutdown();
      }
    });

    test('per-task encoders override the defaults', () async {
      final app = await StemApp.inMemory(
        tasks: [
          FunctionTaskHandler<String>(
            name: 'typed.override',
            entrypoint: (context, args) async {
              return args['secret'] as String;
            },
            metadata: const TaskMetadata(
              argsEncoder: _JsonArgsTaskPayloadEncoder(),
              resultEncoder: _Base64TaskPayloadEncoder(),
            ),
          ),
        ],
      );
      await app.start();
      try {
        final taskId = await app.stem.enqueue(
          'typed.override',
          args: const {'secret': 'payload'},
        );
        final result = await app.stem.waitForTask<String>(taskId);
        expect(result?.value, 'payload');
        final status = await app.backend.get(taskId);
        expect(
          status?.meta[stemResultEncoderMetaKey],
          const _Base64TaskPayloadEncoder().id,
        );
      } finally {
        await app.shutdown();
      }
    });
  });
}

class _Base64TaskPayloadEncoder extends TaskPayloadEncoder {
  const _Base64TaskPayloadEncoder();

  @override
  Object? encode(Object? value) {
    if (value is String) {
      return base64Encode(utf8.encode(value));
    }
    return value;
  }

  @override
  Object? decode(Object? stored) {
    if (stored is String) {
      return utf8.decode(base64Decode(stored));
    }
    return stored;
  }
}

class _JsonArgsTaskPayloadEncoder extends TaskPayloadEncoder {
  const _JsonArgsTaskPayloadEncoder();

  static const _blobKey = '__blob';

  @override
  Object? encode(Object? value) {
    if (value == null) return null;
    final encoded = jsonEncode(value);
    return {_blobKey: base64Encode(utf8.encode(encoded))};
  }

  @override
  Object? decode(Object? stored) {
    if (stored is Map && stored[_blobKey] is String) {
      final blob = stored[_blobKey] as String;
      final decoded = utf8.decode(base64Decode(blob));
      final result = jsonDecode(decoded);
      if (result is Map<String, Object?>) {
        return result;
      }
      return (result as Map).cast<String, Object?>();
    }
    return stored;
  }
}
