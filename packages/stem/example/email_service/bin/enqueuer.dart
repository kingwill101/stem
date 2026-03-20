import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();
  final backendUrl = config.resultBackendUrl;
  final signer = PayloadSigner.maybe(config.signing);

  if (backendUrl == null) {
    stderr.writeln(
      'STEM_RESULT_BACKEND_URL must be provided for the email service.',
    );
    exit(64);
  }

  final tasks = <TaskHandler<Object?>>[
    FunctionTaskHandler<String>(
      name: 'email.send',
      entrypoint: _placeholderEntrypoint,
      options: const TaskOptions(queue: 'emails', maxRetries: 3),
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
      create: () => RedisResultBackend.connect(
        backendUrl,
        tls: config.tls,
      ),
      dispose: (backend) => backend.close(),
    ),
    tasks: tasks,
    signer: signer,
  );

  final router = Router()
    ..post('/send-email', (Request request) async {
      final body = jsonDecode(await request.readAsString()) as Map;
      final to = (body['to'] as String?)?.trim();
      final subject = (body['subject'] as String?)?.trim();
      final emailBody = (body['body'] as String?)?.trim();
      if (to == null ||
          to.isEmpty ||
          subject == null ||
          subject.isEmpty ||
          emailBody == null ||
          emailBody.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing required fields: to, subject, body',
          }),
        );
      }
      final taskId = await client.enqueue(
        'email.send',
        args: {'to': to, 'subject': subject, 'body': emailBody},
        options: const TaskOptions(queue: 'emails'),
      );
      return Response.ok(
        jsonEncode({'taskId': taskId}),
        headers: {'content-type': 'application/json'},
      );
    });

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '8082') ?? 8082;
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Email enqueue API listening on http://${server.address.address}:$port',
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Shutting down email enqueue service ($signal)...');
    await server.close(force: true);
    await client.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);
}

FutureOr<Object?> _placeholderEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) =>
    'noop';
