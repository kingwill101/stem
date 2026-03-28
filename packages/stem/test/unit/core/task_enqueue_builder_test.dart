import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('TaskCall builders', () {
    test('buildCall stores headers/meta and options', () {
      final definition = TaskDefinition<Map<String, Object?>, Object?>(
        name: 'demo.task',
        encodeArgs: (args) => args,
        encodeMeta: (args) => {'from': 'definition'},
      );

      final call = definition.buildCall(
        const {'a': 1},
        headers: const {'h1': 'v1'},
        options: const TaskOptions(queue: 'critical', priority: 5),
        notBefore: DateTime.parse('2025-01-01T00:00:00Z'),
        meta: const {'m1': 'v1'},
        enqueueOptions: const TaskEnqueueOptions(addToParent: false),
      );

      expect(call.headers['h1'], 'v1');
      expect(call.meta['m1'], 'v1');
      expect(call.options?.queue, 'critical');
      expect(call.options?.priority, 5);
      expect(call.notBefore, DateTime.parse('2025-01-01T00:00:00Z'));
      expect(call.enqueueOptions?.addToParent, isFalse);
    });

    test('buildCall preserves definition metadata by default', () {
      final definition = TaskDefinition<Map<String, Object?>, Object?>(
        name: 'demo.task',
        encodeArgs: (args) => args,
        encodeMeta: (args) => {'from': 'definition'},
      );

      final call = definition.buildCall(const {'a': 1});

      expect(call.meta, containsPair('from', 'definition'));
    });

    test('buildCall accepts direct headers, metadata, and options', () {
      final definition = TaskDefinition<Map<String, Object?>, Object?>(
        name: 'demo.task',
        encodeArgs: (args) => args,
      );

      final call = definition.buildCall(
        const {'a': 1},
        headers: const {'h': 'v'},
        meta: const {'m': 1},
        options: const TaskOptions(queue: 'q', priority: 9),
      );

      expect(call.headers, containsPair('h', 'v'));
      expect(call.meta, containsPair('m', 1));
      expect(call.options?.queue, 'q');
      expect(call.options?.priority, 9);
    });

    test('buildCall creates an explicit transport object', () {
      final definition = TaskDefinition<Map<String, Object?>, Object?>(
        name: 'demo.task',
        encodeArgs: (args) => args,
      );

      final call = definition.buildCall(
        const {'a': 1},
        headers: const {'h1': 'v1'},
        options: const TaskOptions(priority: 7),
      );

      expect(call.name, 'demo.task');
      expect(call.resolveOptions().priority, 7);
      expect(call.headers, containsPair('h1', 'v1'));
      expect(call.encodeArgs(), containsPair('a', 1));
    });

    test(
      'TaskCall from buildCall composes with enqueueCall and typed waits',
      () async {
        final definition = TaskDefinition<Map<String, Object?>, String>(
          name: 'demo.task',
          encodeArgs: (args) => args,
          decodeResult: (payload) => 'decoded:$payload',
        );
        final caller = _RecordingTaskResultCaller();
        final call = definition.buildCall(
          const {'a': 1},
          headers: const {'h1': 'v1'},
        );
        final taskId = await caller.enqueueCall(call);
        final result = await call.definition.waitFor(caller, taskId);

        expect(caller.lastCall, isNotNull);
        expect(caller.lastCall!.name, 'demo.task');
        expect(caller.lastCall!.headers, containsPair('h1', 'v1'));
        expect(caller.waitedTaskId, 'task-1');
        expect(result?.value, 'decoded:stored');
      },
    );

    test('buildCall preserves enqueuer dispatch semantics', () async {
      final enqueuer = _RecordingTaskEnqueuer();
      final definition = TaskDefinition<Map<String, Object?>, String>(
        name: 'demo.task',
        encodeArgs: (args) => args,
        decodeResult: (payload) => 'decoded:$payload',
      );

      final taskId = await enqueuer.enqueueCall(
        definition.buildCall(
          const {'a': 1},
          headers: const {'h1': 'v1'},
          options: const TaskOptions(queue: 'critical'),
        ),
      );

      expect(taskId, 'task-1');
      expect(enqueuer.lastCall, isNotNull);
      expect(enqueuer.lastCall!.name, 'demo.task');
      expect(enqueuer.lastCall!.headers, containsPair('h1', 'v1'));
      expect(enqueuer.lastCall!.resolveOptions().queue, 'critical');
    });

    test('TaskCall composes with typed waits', () async {
      final caller = _RecordingTaskResultCaller();
      final definition = TaskDefinition<Map<String, Object?>, String>(
        name: 'demo.task',
        encodeArgs: (args) => args,
        decodeResult: (payload) => 'decoded:$payload',
      );

      final call = definition.buildCall(
        const {'a': 1},
        headers: const {'h1': 'v1'},
      );
      final taskId = await caller.enqueueCall(call);
      final result = await call.definition.waitFor(caller, taskId);

      expect(caller.lastCall, isNotNull);
      expect(caller.lastCall!.name, 'demo.task');
      expect(caller.lastCall!.headers, containsPair('h1', 'v1'));
      expect(caller.waitedTaskId, 'task-1');
      expect(result?.value, 'decoded:stored');
    });

    test('buildCall can be rebuilt with updated headers and meta', () {
      final definition = TaskDefinition<Map<String, Object?>, Object?>(
        name: 'demo.task',
        encodeArgs: (args) => args,
      );
      final updated = definition.buildCall(
        const {'a': 1},
        headers: const {'h2': 'v2'},
        meta: const {'m2': 2},
      );

      expect(updated.headers['h2'], 'v2');
      expect(updated.meta['m2'], 2);
    });

    test(
      'NoArgsTaskDefinition.asDefinition.buildCall builds an empty call',
      () {
      final definition = TaskDefinition.noArgs<void>(name: 'demo.no_args');

      final call = definition.asDefinition.buildCall(
        (),
        headers: const {'h': 'v'},
        meta: const {'m': 1},
      );

      expect(call.name, 'demo.no_args');
      expect(call.encodeArgs(), isEmpty);
      expect(call.headers, containsPair('h', 'v'));
      expect(call.meta, containsPair('m', 1));
      },
    );

    test('NoArgsTaskDefinition.asDefinition.buildCall accepts overrides', () {
      final definition = TaskDefinition.noArgs<void>(name: 'demo.no_args');

      final call = definition.asDefinition.buildCall(
        (),
        options: const TaskOptions(priority: 4),
      );

      expect(call.name, 'demo.no_args');
      expect(call.resolveOptions().priority, 4);
      expect(call.encodeArgs(), isEmpty);
    });

    test(
      'NoArgsTaskDefinition.enqueue uses the TaskEnqueuer surface',
      () async {
      final definition = TaskDefinition.noArgs<void>(name: 'demo.no_args');
      final enqueuer = _RecordingTaskEnqueuer();

      final taskId = await definition.enqueue(
        enqueuer,
        headers: const {'h': 'v'},
        meta: const {'m': 1},
      );

      expect(taskId, 'task-1');
      expect(enqueuer.lastCall, isNotNull);
      expect(enqueuer.lastCall!.name, 'demo.no_args');
      expect(enqueuer.lastCall!.encodeArgs(), isEmpty);
      expect(enqueuer.lastCall!.headers, containsPair('h', 'v'));
      expect(enqueuer.lastCall!.meta, containsPair('m', 1));
      },
    );
  });
}

class _RecordingTaskEnqueuer implements TaskEnqueuer {
  TaskCall<dynamic, dynamic>? lastCall;

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    throw UnimplementedError('enqueue is not used in this test');
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    lastCall = call;
    return 'task-1';
  }

  @override
  Future<String> enqueueValue<T>(
    String name,
    T value, {
    PayloadCodec<T>? codec,
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    throw UnimplementedError('enqueueValue is not used in this test');
  }
}

class _RecordingTaskResultCaller extends _RecordingTaskEnqueuer
    implements TaskResultCaller {
  String? waitedTaskId;

  @override
  Future<TaskStatus?> getTaskStatus(String taskId) async => null;

  @override
  Future<GroupStatus?> getGroupStatus(String groupId) async => null;

  @override
  Future<TaskResult<TResult>?> waitForTask<TResult extends Object?>(
    String taskId, {
    Duration? timeout,
    TResult Function(Object? payload)? decode,
    TResult Function(Map<String, Object?> json)? decodeJson,
    TResult Function(Map<String, Object?> json, int version)?
    decodeVersionedJson,
  }) async {
    waitedTaskId = taskId;
    final value =
        decode?.call('stored') ??
        decodeJson?.call(const {'value': 'stored'}) ??
        decodeVersionedJson?.call(const {'value': 'stored'}, 1);
    return TaskResult<TResult>(
      taskId: taskId,
      status: TaskStatus(
        id: taskId,
        state: TaskState.succeeded,
        attempt: 0,
        payload: 'stored',
      ),
      value: value,
      rawPayload: 'stored',
    );
  }
}
