import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('TaskEnqueueBuilder merges headers/meta and options', () {
    final definition = TaskDefinition<Map<String, Object?>, Object?>(
      name: 'demo.task',
      encodeArgs: (args) => args,
      encodeMeta: (args) => {'from': 'definition'},
    );

    final call =
        TaskEnqueueBuilder(definition: definition, args: const {'a': 1})
            .header('h1', 'v1')
            .meta('m1', 'v1')
            .queue('critical')
            .priority(5)
            .notBefore(DateTime.parse('2025-01-01T00:00:00Z'))
            .enqueueOptions(const TaskEnqueueOptions(addToParent: false))
            .build();

    expect(call.headers['h1'], 'v1');
    expect(call.meta['from'], 'definition');
    expect(call.meta['m1'], 'v1');
    expect(call.options?.queue, 'critical');
    expect(call.options?.priority, 5);
    expect(call.notBefore, DateTime.parse('2025-01-01T00:00:00Z'));
    expect(call.enqueueOptions?.addToParent, isFalse);
  });

  test('TaskEnqueueBuilder delay sets notBefore in the future', () {
    final definition = TaskDefinition<Map<String, Object?>, Object?>(
      name: 'demo.task',
      encodeArgs: (args) => args,
    );

    final start = DateTime.now();
    final call = TaskEnqueueBuilder(
      definition: definition,
      args: const {'a': 1},
    ).delay(const Duration(seconds: 2)).build();

    expect(call.notBefore, isNotNull);
    expect(call.notBefore!.isAfter(start), isTrue);
  });

  test('TaskEnqueueBuilder replaces headers, metadata, and options', () {
    final definition = TaskDefinition<Map<String, Object?>, Object?>(
      name: 'demo.task',
      encodeArgs: (args) => args,
    );

    final call =
        TaskEnqueueBuilder(definition: definition, args: const {'a': 1})
            .headers(const {'h': 'v'})
            .metadata(const {'m': 1})
            .options(const TaskOptions(queue: 'q', priority: 9))
            .build();

    expect(call.headers, containsPair('h', 'v'));
    expect(call.meta, containsPair('m', 1));
    expect(call.options?.queue, 'q');
    expect(call.options?.priority, 9);
  });

  test('TaskDefinition.prepareEnqueue creates a fluent builder', () {
    final definition = TaskDefinition<Map<String, Object?>, Object?>(
      name: 'demo.task',
      encodeArgs: (args) => args,
    );

    final call = definition
        .prepareEnqueue(const {'a': 1})
        .priority(7)
        .header('h1', 'v1')
        .build();

    expect(call.name, 'demo.task');
    expect(call.resolveOptions().priority, 7);
    expect(call.headers, containsPair('h1', 'v1'));
    expect(call.encodeArgs(), containsPair('a', 1));
  });

  test(
    'TaskEnqueueBuilder.build composes with enqueueCall and typed waits',
    () async {
      final definition = TaskDefinition<Map<String, Object?>, String>(
        name: 'demo.task',
        encodeArgs: (args) => args,
        decodeResult: (payload) => 'decoded:$payload',
      );
      final caller = _RecordingTaskResultCaller();
      final call = TaskEnqueueBuilder(
        definition: definition,
        args: const {'a': 1},
      ).header('h1', 'v1').build();
      final taskId = await caller.enqueueCall(call);
      final result = await call.definition.waitFor(caller, taskId);

      expect(caller.lastCall, isNotNull);
      expect(caller.lastCall!.name, 'demo.task');
      expect(caller.lastCall!.headers, containsPair('h1', 'v1'));
      expect(caller.waitedTaskId, 'task-1');
      expect(result?.value, 'decoded:stored');
    },
  );

  test(
    'TaskEnqueueBuilder.build preserves enqueuer dispatch semantics',
    () async {
    final enqueuer = _RecordingTaskEnqueuer();
    final definition = TaskDefinition<Map<String, Object?>, String>(
      name: 'demo.task',
      encodeArgs: (args) => args,
      decodeResult: (payload) => 'decoded:$payload',
    );

    final builder = definition
        .prepareEnqueue(const {'a': 1})
        .header('h1', 'v1')
        .queue('critical');
    final taskId = await enqueuer.enqueueCall(builder.build());

    expect(taskId, 'task-1');
    expect(enqueuer.lastCall, isNotNull);
    expect(enqueuer.lastCall!.name, 'demo.task');
    expect(enqueuer.lastCall!.headers, containsPair('h1', 'v1'));
    expect(enqueuer.lastCall!.resolveOptions().queue, 'critical');
  });

  test('TaskEnqueueBuilder composes with typed waits', () async {
      final caller = _RecordingTaskResultCaller();
      final definition = TaskDefinition<Map<String, Object?>, String>(
        name: 'demo.task',
        encodeArgs: (args) => args,
        decodeResult: (payload) => 'decoded:$payload',
      );

      final builder = definition
          .prepareEnqueue(const {'a': 1})
          .header('h1', 'v1');
      final call = builder.build();
      final taskId = await caller.enqueueCall(call);
      final result = await call.definition.waitFor(caller, taskId);

      expect(caller.lastCall, isNotNull);
      expect(caller.lastCall!.name, 'demo.task');
      expect(caller.lastCall!.headers, containsPair('h1', 'v1'));
      expect(caller.waitedTaskId, 'task-1');
      expect(result?.value, 'decoded:stored');
    },
  );

  test('TaskCall.copyWith updates headers and meta', () {
    final definition = TaskDefinition<Map<String, Object?>, Object?>(
      name: 'demo.task',
      encodeArgs: (args) => args,
    );
    final call = definition
        .prepareEnqueue(const {'a': 1})
        .headers(const {'h': 'v'})
        .metadata(const {'m': 1})
        .build();

    final updated = call.copyWith(
      headers: const {'h2': 'v2'},
      meta: const {'m2': 2},
    );

    expect(updated.headers['h2'], 'v2');
    expect(updated.meta['m2'], 2);
  });

  test('NoArgsTaskDefinition.prepareEnqueue builds an empty payload call', () {
    final definition = TaskDefinition.noArgs<void>(name: 'demo.no_args');

    final call = definition
        .asDefinition
        .prepareEnqueue(())
        .headers(const {'h': 'v'})
        .metadata(const {'m': 1})
        .build();

    expect(call.name, 'demo.no_args');
    expect(call.encodeArgs(), isEmpty);
    expect(call.headers, containsPair('h', 'v'));
    expect(call.meta, containsPair('m', 1));
  });

  test('NoArgsTaskDefinition.prepareEnqueue creates a fluent builder', () {
    final definition = TaskDefinition.noArgs<void>(name: 'demo.no_args');

    final call = definition.asDefinition.prepareEnqueue(()).priority(4).build();

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
    TResult Function(Map<String, dynamic> payload)? decodeJson,
    TResult Function(Map<String, dynamic> payload, int version)?
    decodeVersionedJson,
  }) async {
    waitedTaskId = taskId;
    return TaskResult<TResult>(
      taskId: taskId,
      status: TaskStatus(id: taskId, state: TaskState.succeeded, attempt: 0),
      value: decode?.call('stored'),
      rawPayload: 'stored',
    );
  }

  @override
  Future<TaskResult<TResult>?>
  waitForTaskDefinition<TArgs, TResult extends Object?>(
    String taskId,
    TaskDefinition<TArgs, TResult> definition, {
    Duration? timeout,
  }) async {
    return waitForTask(
      taskId,
      timeout: timeout,
      decode: definition.decodeResult,
    );
  }
}
