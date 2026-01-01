// Production checklist snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:io';

import 'package:stem/stem.dart';

// #region production-signing
Future<void> configureSigning() async {
  final config = StemConfig.fromEnvironment();
  final signer = PayloadSigner.maybe(config.signing);
  final broker = InMemoryBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'audit.log',
        entrypoint: (context, args) async {
          print('Audit log: ${args['message']}');
          return null;
        },
      ),
    );

  final stem = Stem(
    broker: broker,
    backend: backend,
    registry: registry,
    signer: signer,
  );

  final worker = Worker(
    broker: broker,
    backend: backend,
    registry: registry,
    signer: signer,
  );

  await stem.enqueue('audit.log', args: {'message': 'hello'});
  await worker.shutdown();
}
// #endregion production-signing

Future<void> main() async {
  if (!Platform.environment.containsKey('STEM_BROKER_URL')) {
    print('Set STEM_BROKER_URL to run the signing example.');
    return;
  }
  await configureSigning();
}
