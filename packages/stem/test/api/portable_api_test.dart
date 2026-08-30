import 'package:stem/portable.dart';
import 'package:test/test.dart';

void main() {
  test(
    'portable entrypoint supports publish-only enqueue and processing',
    () async {
      final definition = TaskDefinition<Map<String, Object?>, Object?>(
        name: 'portable.echo',
        encodeArgs: (args) => args,
        decodeArgs: (args) => args,
      );
      final handler = definition.handler(
        entrypoint: (context, args) async => args,
        executionMode: TaskExecutionMode.inline,
      );
      final publisher = _Publisher();
      final stem = Stem.withPublisher(
        publisher: publisher,
        tasks: [handler],
      );

      final id = await stem.enqueueCall(
        definition.buildCall(const {'value': 'portable'}),
      );
      final envelope = publisher.envelopes.single;
      final processor = TaskProcessor(
        registry: InMemoryTaskRegistry()..register(handler),
      );
      final outcome = await processor.process(envelope);

      expect(id, envelope.id);
      expect(outcome, isA<TaskProcessSuccess>());
      expect((outcome as TaskProcessSuccess).value, {'value': 'portable'});
    },
  );
}

class _Publisher implements TaskPublisher {
  final List<Envelope> envelopes = [];

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    envelopes.add(envelope);
  }
}
