import 'package:stem/stem.dart';
import 'package:test/test.dart';

class _Args {
  const _Args(this.value);
  final int value;
}

void main() {
  group('FakeStem', () {
    test('records enqueueCall requests', () async {
      final fake = FakeStem();
      final definition = TaskDefinition<_Args, void>(
        name: 'demo.task',
        encodeArgs: (args) => {'value': args.value},
      );

      final call = definition(const _Args(42));
      final id = await fake.enqueueCall(call);

      expect(id, isNotEmpty);
      expect(fake.enqueues, hasLength(1));
      final recorded = fake.enqueues.single;
      expect(recorded.id, id);
      expect(recorded.name, 'demo.task');
      expect(recorded.args['value'], 42);
      expect(recorded.headers, isEmpty);
      expect(recorded.options.queue, 'default');
      expect(recorded.call, isNotNull);
    });

    test('records map-based enqueue', () async {
      final fake = FakeStem();
      final id = await fake.enqueue(
        'demo.raw',
        args: const {'value': 5},
        headers: const {'x': '1'},
        options: const TaskOptions(queue: 'custom'),
        meta: const {'source': 'test'},
      );

      expect(id, isNotEmpty);
      final recorded = fake.enqueues.single;
      expect(recorded.name, 'demo.raw');
      expect(recorded.args['value'], 5);
      expect(recorded.headers['x'], '1');
      expect(recorded.options.queue, 'custom');
      expect(recorded.meta['source'], 'test');
      expect(recorded.call, isNull);
    });
  });
}
