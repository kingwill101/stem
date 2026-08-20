import 'package:stem/stable.dart';
import 'package:test/test.dart';

class _StableArgs {
  const _StableArgs(this.value);

  final int value;
}

void main() {
  test('stable entrypoint supports typed registration and enqueue', () async {
    final definition = TaskDefinition<_StableArgs, int>.codec(
      name: 'stable.api.double',
      argsCodec: PayloadCodec<_StableArgs>.map(
        encode: (args) => {'value': args.value},
        decode: (payload) => _StableArgs(payload['value']! as int),
      ),
    );
    final handler = definition.handler(
      entrypoint: (context, args) async => args.value * 2,
      executionMode: TaskExecutionMode.inline,
    );
    expect(handler.executionMode, TaskExecutionMode.inline);
    final app = await StemApp.inMemory(tasks: [handler]);

    try {
      await app.start();
      final taskId = await app.enqueueCall(
        definition.buildCall(const _StableArgs(21)),
      );
      final result = await app.waitForTask<int>(
        taskId,
        timeout: const Duration(seconds: 2),
        decode: (payload) => payload! as int,
      );

      expect(result?.value, 42);
    } finally {
      await app.shutdown();
    }
  });
}
