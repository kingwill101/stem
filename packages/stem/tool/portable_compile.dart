import 'package:stem/portable.dart';

Future<void> main() async {
  final definition = TaskDefinition<Map<String, Object?>, Object?>(
    name: 'portable.compile',
    encodeArgs: (args) => args,
    decodeArgs: (args) => args,
  );
  final handler = definition.handler(
    entrypoint: (context, args) async => args,
    executionMode: TaskExecutionMode.inline,
  );
  final publisher = _CompilePublisher();
  final stem = Stem.withPublisher(
    publisher: publisher,
    tasks: [handler],
  );
  await stem.enqueueCall(definition.buildCall(const {'portable': true}));
  final processor = TaskProcessor(
    registry: InMemoryTaskRegistry()..register(handler),
  );
  final outcome = await processor.process(publisher.envelope!);
  if (outcome is! TaskProcessSuccess) {
    throw StateError('Unexpected portable processing outcome: $outcome');
  }
}

class _CompilePublisher implements TaskPublisher {
  Envelope? envelope;

  @override
  Future<void> publish(Envelope envelope, {RoutingInfo? routing}) async {
    this.envelope = envelope;
  }
}
