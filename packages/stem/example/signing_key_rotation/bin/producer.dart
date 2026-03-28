import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_signing_key_rotation/shared.dart';

Future<void> main() async {
  // #region signing-rotation-producer-config
  final config = StemConfig.fromEnvironment();
  // #endregion signing-rotation-producer-config
  final backendUrl = config.resultBackendUrl ?? config.brokerUrl;
  // #region signing-rotation-producer-signer
  final signer = PayloadSigner.maybe(config.signing);
  // #endregion signing-rotation-producer-signer

  final tasks = buildTasks();
  // #region signing-rotation-producer-stem
  final client = await StemClient.fromUrl(
    config.brokerUrl,
    adapters: [StemRedisAdapter(tls: config.tls)],
    overrides: StemStoreOverrides(backend: backendUrl),
    tasks: tasks,
    signer: signer,
  );
  // #endregion signing-rotation-producer-stem

  final taskCount = _parseInt('TASKS', fallback: 5, min: 1);
  // #region signing-rotation-producer-active-key
  final keyId = config.signing.activeKeyId ??
      Platform.environment['STEM_SIGNING_ACTIVE_KEY'] ??
      'unknown';
  stdout.writeln(
    '[producer] broker=${config.brokerUrl} backend=$backendUrl '
    'signing=${config.signing.isEnabled ? 'on' : 'off'} '
    'activeKey=$keyId tasks=$taskCount',
  );
  // #endregion signing-rotation-producer-active-key

  // #region signing-rotation-producer-enqueue
  const options = TaskOptions(queue: rotationQueue);
  for (var i = 0; i < taskCount; i += 1) {
    final label = 'rotation-${i + 1}';
    final id = await client.enqueue(
      'rotation.demo',
      options: options,
      args: {'label': label, 'key': keyId},
    );
    stdout.writeln('[producer] enqueued $label id=$id');
  }
  // #endregion signing-rotation-producer-enqueue

  await client.close();
}

int _parseInt(String key, {required int fallback, int min = 0}) {
  final raw = Platform.environment[key];
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < min) return fallback;
  return parsed;
}
