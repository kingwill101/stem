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
  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<String>(
      name: 'secure.report',
      entrypoint: _noopEntrypoint,
      options: TaskOptions(queue: config.defaultQueue),
    ),
  ];

  final client = await StemClient.create(
    broker: StemBrokerFactory(
      create: () => RedisStreamsBroker.connect(
        config.brokerUrl,
        tls: config.tls,
      ),
      dispose: (broker) => broker.close(),
    ),
    backend: StemBackendFactory(
      create: () => RedisResultBackend.connect(backendUrl, tls: config.tls),
      dispose: (backend) => backend.close(),
    ),
    tasks: tasks,
    signer: PayloadSigner.maybe(config.signing),
  );

  final jobs = [
    {'customerId': 'cust-1001', 'amount': 1250.75},
    {'customerId': 'cust-2002', 'amount': 880.10},
    {'customerId': 'cust-3003', 'amount': 430.00},
  ];

  for (final job in jobs) {
    final box = await cipher.encrypt(
      utf8.encode(jsonEncode(job)),
      secretKey: secretKey,
      nonce: cipher.newNonce(),
    );

    final payload = {
      'ciphertext': base64Encode(box.cipherText),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
    };

    final taskId = await client.enqueue(
      'secure.report',
      args: payload,
      options: TaskOptions(queue: config.defaultQueue),
    );
    stdout.writeln('Enqueued secure task $taskId for ${job['customerId']}');
  }

  await client.close();
}

FutureOr<Object?> _noopEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    'noop';

String _requireEnv(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('Missing required environment variable $name');
  }
  return value;
}
