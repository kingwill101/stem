import 'dart:isolate';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/task_invocation.dart';
import 'package:test/test.dart';

class _CapturingEnqueuer implements TaskEnqueuer {
  _CapturingEnqueuer(this._taskId);

  final String _taskId;
  Map<String, String>? lastHeaders;
  Map<String, Object?>? lastMeta;
  TaskEnqueueOptions? lastOptions;
  TaskCall<dynamic, dynamic>? lastCall;

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    lastHeaders = headers;
    lastMeta = meta;
    lastOptions = enqueueOptions;
    return _taskId;
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    lastCall = call;
    lastOptions = enqueueOptions;
    return _taskId;
  }
}

void main() {
  test('TaskInvocationContext.local merges headers/meta and lineage', () async {
    final enqueuer = _CapturingEnqueuer('task-1');
    final context = TaskInvocationContext.local(
      id: 'root-task',
      headers: const {'h1': 'v1'},
      meta: const {'m1': 'v1'},
      attempt: 2,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
      enqueuer: enqueuer,
    );

    await context.enqueue(
      'child',
      headers: const {'h2': 'v2'},
      meta: const {'m2': 'v2'},
    );

    expect(enqueuer.lastHeaders, containsPair('h1', 'v1'));
    expect(enqueuer.lastHeaders, containsPair('h2', 'v2'));
    expect(enqueuer.lastMeta, containsPair('m1', 'v1'));
    expect(enqueuer.lastMeta, containsPair('m2', 'v2'));
    expect(enqueuer.lastMeta, containsPair('stem.parentTaskId', 'root-task'));
    expect(enqueuer.lastMeta, containsPair('stem.parentAttempt', 2));
  });

  test('TaskInvocationContext.local throws when enqueuer missing', () async {
    final context = TaskInvocationContext.local(
      id: 'no-enqueuer',
      headers: const {},
      meta: const {},
      attempt: 0,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
    );

    expect(
      () => context.enqueue('task'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => context.enqueueCall(
        const TaskDefinition<Map<String, Object?>, Object?>(
          name: 'demo',
          encodeArgs: _encodeArgs,
        ).call(const {'a': 1}),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'TaskInvocationContext.local enqueueCall merges call metadata',
    () async {
      final enqueuer = _CapturingEnqueuer('task-2');
      final context = TaskInvocationContext.local(
        id: 'root-task',
        headers: const {'h1': 'v1'},
        meta: const {'m1': 'v1'},
        attempt: 1,
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {Map<String, Object?>? data}) async {},
        enqueuer: enqueuer,
      );

      final definition = TaskDefinition<Map<String, Object?>, Object?>(
        name: 'demo.call',
        encodeArgs: (args) => args,
      );
      final call = definition.call(
        const {'value': 1},
        headers: const {'h2': 'v2'},
        meta: const {'m2': 'v2'},
      );

      await context.enqueueCall(call);

      final merged = enqueuer.lastCall;
      expect(merged, isNotNull);
      expect(merged!.headers['h1'], 'v1');
      expect(merged.headers['h2'], 'v2');
      expect(merged.meta['stem.parentTaskId'], 'root-task');
    },
  );

  test('TaskInvocationContext.remote sends control signals', () async {
    final control = ReceivePort();
    addTearDown(control.close);

    final signals = <TaskInvocationSignal>[];
    control.listen((message) {
      if (message is EnqueueTaskSignal) {
        signals.add(message);
        message.replyPort.send(const TaskEnqueueResponse(taskId: 'remote-id'));
      } else if (message is TaskInvocationSignal) {
        signals.add(message);
      }
    });

    final context = TaskInvocationContext.remote(
      id: 'remote-task',
      controlPort: control.sendPort,
      headers: const {},
      meta: const {},
      attempt: 0,
    );

    // Cascades can't be used here because the calls are awaited separately.
    // ignore: cascade_invocations
    context.heartbeat();
    await context.extendLease(const Duration(seconds: 1));
    await context.progress(25, data: const {'step': 1});

    final taskId = await context.enqueue('demo.remote');
    expect(taskId, 'remote-id');

    expect(signals.any((signal) => signal is HeartbeatSignal), isTrue);
    expect(signals.any((signal) => signal is ExtendLeaseSignal), isTrue);
    expect(signals.any((signal) => signal is ProgressSignal), isTrue);
    expect(signals.any((signal) => signal is EnqueueTaskSignal), isTrue);
  });

  test('TaskInvocationContext.remote surfaces enqueue errors', () async {
    final control = ReceivePort();
    addTearDown(control.close);

    control.listen((message) {
      if (message is EnqueueTaskSignal) {
        message.replyPort.send(const TaskEnqueueResponse(error: 'nope'));
      }
    });

    final context = TaskInvocationContext.remote(
      id: 'remote-task',
      controlPort: control.sendPort,
      headers: const {},
      meta: const {},
      attempt: 0,
    );

    await expectLater(
      () => context.enqueue('demo.remote'),
      throwsA(isA<StateError>()),
    );
  });

  test('TaskInvocationContext.retry throws TaskRetryRequest', () {
    final context = TaskInvocationContext.local(
      id: 'retry-task',
      headers: const {},
      meta: const {},
      attempt: 0,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
      enqueuer: _CapturingEnqueuer('noop'),
    );

    expect(
      () => context.retry(countdown: const Duration(seconds: 5)),
      throwsA(isA<TaskRetryRequest>()),
    );
  });
}

Map<String, Object?> _encodeArgs(Map<String, Object?> args) => args;
