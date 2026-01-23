import 'package:stem/src/core/contracts.dart';
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
}
