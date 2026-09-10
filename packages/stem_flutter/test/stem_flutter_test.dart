import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:stem/stem.dart' show FunctionTaskHandler;
import 'package:stem_flutter/stem_flutter.dart';

Future<Object?> _isolateTask(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async => Isolate.current.debugName;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final doubleTask = TaskDefinition<int, int>(
    name: 'double',
    encodeArgs: (value) => {'value': value},
    decodeArgs: (args) => args['value']! as int,
    defaultOptions: const TaskOptions(queue: 'math'),
  );

  test(
    'returns the core app with explicit start and typed task APIs',
    () async {
      final app = await StemFlutter.createApp(
        module: StemModule(
          tasks: [
            doubleTask.handler(entrypoint: (context, value) async => value * 2),
          ],
        ),
      );
      addTearDown(app.shutdown);

      expect(app, isA<StemApp>());
      expect(app.isStarted, isFalse);
      expect(app.worker.concurrency, 1);
      expect(app.worker.prefetch, 1);
      expect(app.worker.lifecycleConfig.installSignalHandlers, isFalse);

      final id = await doubleTask.enqueue(app, 21);
      expect(await app.broker.pendingCount('math'), 1);
      expect((await app.getTaskStatus(id))?.state, TaskState.queued);

      await app.start();
      final result = await app.waitForTask<int>(
        id,
        timeout: const Duration(seconds: 5),
      );
      expect(result?.value, 42);
      expect((await app.getTaskStatus(id))?.state, TaskState.succeeded);

      await app.shutdown();
      await app.shutdown();
      expect(app.isStarted, isFalse);
      await expectLater(app.start(), throwsStateError);
    },
  );

  test(
    'keeps core isolated execution without a Flutter worker protocol',
    () async {
      final app = await StemFlutter.createApp(
        tasks: [
          FunctionTaskHandler<String>(
            name: 'isolate-name',
            entrypoint: _isolateTask,
          ),
        ],
      );
      addTearDown(app.shutdown);
      await app.start();
      final id = await app.enqueue('isolate-name');
      final result = await app.waitForTask<String>(
        id,
        timeout: const Duration(seconds: 10),
      );
      expect(result?.value, isNotNull);
      expect(result?.value, isNot(Isolate.current.debugName));
    },
  );

  test('preserves worker overrides and core registry registration', () async {
    final app = await StemFlutter.createApp(
      workerConfig: const StemWorkerConfig(
        concurrency: 2,
        prefetch: 3,
        queue: 'math',
      ),
    );
    addTearDown(app.shutdown);
    app.registerTask(
      doubleTask.handler(entrypoint: (context, value) async => value * 2),
    );
    expect(app.worker.concurrency, 2);
    expect(app.worker.prefetch, 3);
    expect(app.worker.lifecycleConfig.installSignalHandlers, isFalse);
    expect(app.registry.resolve('double'), isNotNull);
    await app.start();
    final id = await app.enqueueCall(doubleTask.buildCall(4));
    expect(
      (await app.waitForTask<int>(
        id,
        timeout: const Duration(seconds: 5),
      ))?.value,
      8,
    );
  });
}
