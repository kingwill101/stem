import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();
  final secretKey = SecretKey(base64Decode(_requireEnv('PAYLOAD_SECRET')));
  final cipher = AesGcm.with256bits();

  // Build Stem client
  final broker = await RedisStreamsBroker.connect(config.brokerUrl);
  final backend = await RedisResultBackend.connect(config.resultBackendUrl!);

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'secure.report',
        entrypoint: _noopEntrypoint,
        options: TaskOptions(queue: config.defaultQueue),
      ),
    );

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );

  final jobs = [
    {'customerId': 'cust-1001', 'amount': 1250.75},
    {'customerId': 'cust-2002', 'amount': 880.10},
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

    final id = await stem.enqueue(
      'secure.report',
      args: payload,
      options: TaskOptions(queue: config.defaultQueue),
    );
    stdout.writeln('Container task $id for ${job['customerId']}');
  }

  await broker.close();
  await backend.close();
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
