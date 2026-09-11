import 'dart:convert';
import 'dart:io';

import 'package:workflow_host_prototype/example_binary_codec.dart';
import 'package:workflow_host_prototype/workflow_host.dart';

Future<void> main() async {
  try {
    const codec = BinaryMessageCodec();
    final bytes = codec.encoder.convert(const BinaryMessage('Ada 🌱'));
    // Model a persistent adapter's JSON envelope, not raw binary transport.
    final persisted = jsonDecode(jsonEncode({'input': bytes})) as Map;
    print(
      'Binary bytes: ${bytes.length}; '
      'JSON reconstruction: ${codec.decode(persisted['input']).text}',
    );

    final greeting = HostedWorkflow<BinaryMessage, BinaryMessage>(
      name: 'binary-greeting',
      run: (flow, input) async {
        await flow.step(
          'greeting',
          () => BinaryMessage('Hello, ${input.text}!'),
        );
        return flow.step<BinaryMessage>(
          'greeting',
          () => throw StateError('Must replay the checkpoint'),
        );
      },
    );
    await WorkflowHost.run<void>(
      workflows: [greeting],
      codecs: PayloadCodecRegistry()..register<BinaryMessage>(codec),
      body: (host) async {
        final result = await host.execute(
          greeting,
          const BinaryMessage('Ada 🌱'),
        );
        print(result.text);
      },
    );
  } catch (error, stack) {
    stderr
      ..writeln(error)
      ..writeln(stack);
    exitCode = 1;
  }
}
