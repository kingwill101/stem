import 'dart:async';
import 'dart:isolate';

import 'package:stem/src/core/task_invocation.dart';
import 'package:stem/src/worker/isolate_pool.dart';
import 'package:test/test.dart';

void main() {
  group('TaskIsolatePool run cleanup', () {
    test('hard timeouts release ports and allow subsequent attempts', () async {
      final results = await _runInHost(_timeouts);

      expect(results, hasLength(4));
      for (final result in results.take(3)) {
        expect(
          result,
          isA<TaskExecutionTimeout>()
              .having((value) => value.taskName, 'taskName', 'test.task')
              .having(
                (value) => value.limit,
                'limit',
                const Duration(milliseconds: 50),
              ),
        );
      }
      expect(
        results.last,
        isA<TaskExecutionSuccess>().having((value) => value.value, 'value', 3),
      );
    });

    test('disposing an active run settles it and releases ports', () async {
      final results = await _runInHost(_disposeActive);

      expect(results, hasLength(1));
      expect(
        results.single,
        isA<TaskExecutionFailure>().having(
          (value) => value.error,
          'error',
          isA<StateError>(),
        ),
      );
    });

    test(
      'a send failure releases ports and leaves the worker usable',
      () async {
        final results = await _runInHost(_sendFailure);

        expect(results, hasLength(2));
        expect(results.first, isA<TaskExecutionFailure>());
        expect(results.last, isA<TaskExecutionSuccess>());
      },
    );
  });
}

typedef _Scenario = Future<List<TaskExecutionResult>> Function();

// A pool-owning isolate must exit naturally after the scenario. Merely awaiting
// execute/dispose would miss reply and control ports leaked by a killed worker.
Future<List<TaskExecutionResult>> _runInHost(_Scenario scenario) async {
  final events = ReceivePort();
  final exited = Completer<void>();
  final messages = <Object?>[];
  final subscription = events.listen((message) {
    if (message == null) {
      exited.complete();
    } else {
      messages.add(message);
    }
  });
  final host = await Isolate.spawn(
    _host,
    (events.sendPort, scenario),
    onExit: events.sendPort,
    onError: events.sendPort,
  );
  try {
    await exited.future.timeout(const Duration(seconds: 5));
    // Unhandled asynchronous errors are also sent here and fail this assertion.
    expect(messages, hasLength(1));
    return messages.single! as List<TaskExecutionResult>;
  } finally {
    host.kill(priority: Isolate.immediate);
    await subscription.cancel();
    events.close();
  }
}

Future<void> _host((SendPort, _Scenario) request) async {
  request.$1.send(await request.$2());
}

Future<TaskExecutionResult> _execute(
  TaskIsolatePool pool,
  TaskEntrypoint entrypoint, {
  Map<String, Object?> args = const {},
  int attempt = 0,
  Duration? hardTimeout,
}) => pool.execute(
  entrypoint,
  args,
  const {},
  const {},
  attempt,
  (_) {},
  taskName: 'test.task',
  taskId: 'test-$attempt',
  hardTimeout: hardTimeout,
);

Future<List<TaskExecutionResult>> _timeouts() async {
  final pool = TaskIsolatePool(size: 1);
  await pool.start();
  try {
    final attempts = [
      for (var attempt = 0; attempt < 3; attempt++)
        _execute(
          pool,
          (_, _) => Completer<Object?>().future,
          attempt: attempt,
          hardTimeout: const Duration(milliseconds: 50),
        ),
      _execute(pool, (context, _) => context.attempt, attempt: 3),
    ];
    return await Future.wait(attempts);
  } finally {
    await pool.dispose();
  }
}

Future<List<TaskExecutionResult>> _disposeActive() async {
  final pool = TaskIsolatePool(size: 1);
  final started = ReceivePort();
  await pool.start();
  try {
    final result = _execute(
      pool,
      (_, args) {
        (args['started']! as SendPort).send(true);
        return Completer<Object?>().future;
      },
      args: {'started': started.sendPort},
    );
    await started.first;
    await pool.dispose();
    await pool.dispose();
    return [await result];
  } finally {
    started.close();
    await pool.dispose();
  }
}

Future<List<TaskExecutionResult>> _sendFailure() async {
  final pool = TaskIsolatePool(size: 1);
  final unsendable = ReceivePort();
  await pool.start();
  try {
    final failure = await _execute(
      pool,
      (_, _) => 'unused',
      args: {'unsendable': unsendable},
    );
    final success = await _execute(pool, (_, _) => 'ok');
    return [failure, success];
  } finally {
    unsendable.close();
    await pool.dispose();
  }
}
