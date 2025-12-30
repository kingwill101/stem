import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_signing_key_rotation/shared.dart';

Future<void> main() async {
  final config = StemConfig.fromEnvironment();
  final broker = await connectBroker(config.brokerUrl, tls: config.tls);
  final backendUrl = config.resultBackendUrl ?? config.brokerUrl;
  final backend = await connectBackend(backendUrl, tls: config.tls);
  final signer = PayloadSigner.maybe(config.signing);

  final registry = buildRegistry();
  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    signer: signer,
  );

  final taskCount = _parseInt('TASKS', fallback: 5, min: 1);
  final keyId = config.signing.activeKeyId ??
      Platform.environment['STEM_SIGNING_ACTIVE_KEY'] ??
      'unknown';
  stdout.writeln(
    '[producer] broker=${config.brokerUrl} backend=$backendUrl '
    'signing=${config.signing.isEnabled ? 'on' : 'off'} '
    'activeKey=$keyId tasks=$taskCount',
  );

  const options = TaskOptions(queue: rotationQueue);
  for (var i = 0; i < taskCount; i += 1) {
    final label = 'rotation-${i + 1}';
    final id = await stem.enqueue(
      'rotation.demo',
      options: options,
      args: {'label': label, 'key': keyId},
    );
    stdout.writeln('[producer] enqueued $label id=$id');
  }

  await broker.close();
  await backend.close();
}

int _parseInt(String key, {required int fallback, int min = 0}) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < min) return fallback;
  return parsed;
}
