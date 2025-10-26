import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();
  final secretKey = SecretKey(base64Decode(_requireEnv('PAYLOAD_SECRET')));
  final cipher = AesGcm.with256bits();

  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be set for the encrypted example.',
    );
  }

  final broker = await RedisStreamsBroker.connect(
    config.brokerUrl,
    tls: config.tls,
  );
  final backend = await RedisResultBackend.connect(backendUrl, tls: config.tls);

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'secure.report',
        entrypoint: (context, args) =>
            _encryptedEntrypoint(context, args, cipher, secretKey),
        options: TaskOptions(
          queue: config.defaultQueue,
          maxRetries: 5,
          softTimeLimit: const Duration(seconds: 5),
        ),
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    queue: config.defaultQueue,
    consumerName: 'encrypted-worker-1',
    concurrency: 2,
  );

  await worker.start();
  stdout.writeln('Encrypted worker consuming from "${config.defaultQueue}"');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Stopping encrypted worker ($signal)...');
    await worker.shutdown();
    await broker.close();
    await backend.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await Completer<void>().future;
}

Future<String> _encryptedEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
  AesGcm cipher,
  SecretKey secretKey,
) async {
  final cipherText = base64Decode(args['ciphertext'] as String);
  final nonce = base64Decode(args['nonce'] as String);
  final mac = Mac(base64Decode(args['mac'] as String));

  final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
  final plainBytes = await cipher.decrypt(secretBox, secretKey: secretKey);

  final payload = jsonDecode(utf8.decode(plainBytes)) as Map<String, Object?>;
  final customerId = payload['customerId'];
  final amount = payload['amount'];

  context.heartbeat();
  stdout.writeln(
    '🔐 Generated secure report for $customerId (amount: $amount)',
  );
  context.progress(1.0, data: payload);
  return 'Report complete for $customerId';
}

String _requireEnv(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('Missing required environment variable $name');
  }
  return value;
}
