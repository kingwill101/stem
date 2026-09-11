import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late StemFlutterStorageLayout layout;
  final task = TaskDefinition<int, int>(
    name: 'background.increment',
    encodeArgs: (value) => {'value': value},
    decodeArgs: (args) => args['value']! as int,
    defaultOptions: const TaskOptions(queue: 'background'),
  );

  Future<StemApp> open(StemModule module) => StemFlutterSqlite.createApp(
    layout: layout,
    module: module,
    storage: const StemFlutterSqliteConfig(
      pollInterval: Duration(milliseconds: 25),
    ),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('stem_background_');
    layout = await StemFlutterStorageLayout.forRoot(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('fresh callback drains persisted work and closes its runtime', () async {
    final module = StemModule(
      tasks: [task.handler(entrypoint: (context, value) async => value + 1)],
    );
    final producer = await open(module);
    addTearDown(producer.shutdown);
    final ids = [
      for (var value = 0; value < 3; value++)
        await task.enqueue(producer, value),
    ];
    await producer.shutdown();

    final callback = await open(module);
    addTearDown(callback.shutdown);
    final outcome = await callback.runUntilIdle(
      budget: const Duration(seconds: 10),
      idleTimeout: const Duration(milliseconds: 300),
    );
    expect(outcome.reason, WorkerRunStopReason.idle);
    expect(outcome.deliveriesProcessed, 3);
    expect(outcome.error, isNull);
    expect(callback.isStarted, isFalse);
    await expectLater(callback.start(), throwsStateError);

    final observer = await open(module);
    addTearDown(observer.shutdown);
    expect(await observer.broker.pendingCount('background'), 0);
    expect(await observer.broker.inflightCount('background'), 0);
    for (var index = 0; index < ids.length; index++) {
      expect(
        (await task.waitFor(
          observer,
          ids[index],
          timeout: const Duration(seconds: 2),
        ))?.value,
        index + 1,
      );
    }
  });

  test('an idle callback leaves future-dated work durable', () async {
    final module = StemModule(
      tasks: [task.handler(entrypoint: (context, value) async => value + 1)],
    );
    final producer = await open(module);
    addTearDown(producer.shutdown);
    final id = await task.enqueue(
      producer,
      10,
      notBefore: DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    await producer.shutdown();

    final callback = await open(module);
    addTearDown(callback.shutdown);
    final outcome = await callback.runUntilIdle(
      budget: const Duration(seconds: 10),
      idleTimeout: const Duration(milliseconds: 300),
    );
    expect(outcome.reason, WorkerRunStopReason.idle);
    expect(outcome.deliveriesProcessed, 0);

    final observer = await open(module);
    addTearDown(observer.shutdown);
    expect((await observer.getTaskStatus(id))?.state, TaskState.queued);
  });

  test(
    'cancellation drains a claimed task and leaves the next for another wake',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final cancel = Completer<void>();
      final module = StemModule(
        tasks: [
          task.handler(
            entrypoint: (context, value) async {
              if (value == 0) {
                entered.complete();
                await release.future;
              }
              return value + 1;
            },
          ),
        ],
      );
      final producer = await open(module);
      addTearDown(producer.shutdown);
      final first = await task.enqueue(producer, 0);
      final second = await task.enqueue(producer, 1);
      await producer.shutdown();

      final callback = await open(module);
      addTearDown(callback.shutdown);
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var returned = false;
      final running = callback
          .runUntilIdle(
            budget: const Duration(seconds: 10),
            cancellation: cancel.future,
          )
          .then((outcome) {
            returned = true;
            return outcome;
          });
      await entered.future.timeout(const Duration(seconds: 5));
      cancel.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        returned,
        isFalse,
        reason: 'Inline work still owns its resources.',
      );
      release.complete();
      final outcome = await running.timeout(const Duration(seconds: 5));
      expect(outcome.reason, WorkerRunStopReason.cancelled);
      expect(outcome.deliveriesProcessed, 1);

      final nextCallback = await open(module);
      addTearDown(nextCallback.shutdown);
      expect(
        (await nextCallback.getTaskStatus(first))?.state,
        TaskState.succeeded,
      );
      expect(
        (await nextCallback.getTaskStatus(second))?.state,
        TaskState.queued,
      );
      final nextOutcome = await nextCallback.runUntilIdle(
        budget: const Duration(seconds: 10),
        idleTimeout: const Duration(milliseconds: 300),
      );
      expect(nextOutcome.reason, WorkerRunStopReason.idle);
      expect(nextOutcome.deliveriesProcessed, 1);
    },
  );

  test(
    'admission deadline does not close stores under active inline work',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final module = StemModule(
        tasks: [
          task.handler(
            entrypoint: (context, value) async {
              if (value == 0) {
                entered.complete();
                await release.future;
              }
              return value + 1;
            },
          ),
        ],
      );
      final producer = await open(module);
      addTearDown(producer.shutdown);
      final first = await task.enqueue(producer, 0);
      final second = await task.enqueue(producer, 1);
      await producer.shutdown();

      final callback = await open(module);
      addTearDown(callback.shutdown);
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var returned = false;
      final running = callback
          .runUntilIdle(
            budget: const Duration(seconds: 2),
            shutdownReserve: const Duration(seconds: 1),
          )
          .then((outcome) {
            returned = true;
            return outcome;
          });
      await entered.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(returned, isFalse);
      release.complete();
      final outcome = await running.timeout(const Duration(seconds: 5));
      expect(outcome.reason, WorkerRunStopReason.budgetExceeded);
      expect(outcome.deliveriesProcessed, 1);

      final observer = await open(module);
      addTearDown(observer.shutdown);
      expect((await observer.getTaskStatus(first))?.state, TaskState.succeeded);
      expect((await observer.getTaskStatus(second))?.state, TaskState.queued);
      expect(await observer.broker.inflightCount('background'), 0);
    },
  );
}
