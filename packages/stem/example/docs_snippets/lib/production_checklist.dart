// Production checklist snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:io';

import 'package:stem/stem.dart';

// #region production-signing-config
Future<void> configureSigning() async {
  final config = StemConfig.fromEnvironment();
  // #endregion production-signing-config

  // #region production-signing-signer
  final signer = PayloadSigner.maybe(config.signing);
  // #endregion production-signing-signer

  // #region production-signing-registry
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
  // #endregion production-signing-registry

  // #region production-signing-runtime
  // #region production-signing-stem
  final stem = Stem(
    broker: broker,
    backend: backend,
    registry: registry,
    signer: signer,
  );
  // #endregion production-signing-stem

  // #region production-signing-worker
  final worker = Worker(
    broker: broker,
    backend: backend,
    registry: registry,
    signer: signer,
  );
  // #endregion production-signing-worker
  // #endregion production-signing-runtime

  // #region production-signing-enqueue
  await stem.enqueue('audit.log', args: {'message': 'hello'});
  // #endregion production-signing-enqueue

  // #region production-signing-shutdown
  await worker.shutdown();
  await backend.close();
  await broker.close();
  // #endregion production-signing-shutdown
}

Future<void> main() async {
  if (!Platform.environment.containsKey('STEM_BROKER_URL')) {
    print('Set STEM_BROKER_URL to run the signing example.');
    return;
  }
  await configureSigning();
}
