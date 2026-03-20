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

  test('TaskCall.copyWith updates headers and meta', () {
    final definition = TaskDefinition<Map<String, Object?>, Object?>(
      name: 'demo.task',
      encodeArgs: (args) => args,
    );
    final call = definition.call(
      const {'a': 1},
      headers: const {'h': 'v'},
      meta: const {'m': 1},
    );

    final updated = call.copyWith(
      headers: const {'h2': 'v2'},
      meta: const {'m2': 2},
    );

    expect(updated.headers['h2'], 'v2');
    expect(updated.meta['m2'], 2);
  });

  test('NoArgsTaskDefinition.call encodes an empty payload', () {
    final definition = TaskDefinition.noArgs<void>(name: 'demo.no_args');

    final call = definition.call(
      headers: const {'h': 'v'},
      meta: const {'m': 1},
    );

    expect(call.name, 'demo.no_args');
    expect(call.encodeArgs(), isEmpty);
    expect(call.headers, containsPair('h', 'v'));
    expect(call.meta, containsPair('m', 1));
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
