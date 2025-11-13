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
  });
}
