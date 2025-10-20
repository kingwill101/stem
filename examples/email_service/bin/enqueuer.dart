import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();
  final broker = await RedisStreamsBroker.connect(config.brokerUrl);
  final backend = config.resultBackendUrl != null
      ? await RedisResultBackend.connect(config.resultBackendUrl!)
      : null;
  final signer = PayloadSigner.maybe(config.signing);

  if (backend == null) {
    stderr.writeln(
      'STEM_RESULT_BACKEND_URL must be provided for the email service.',
    );
    exit(64);
  }

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'email.send',
        entrypoint: _placeholderEntrypoint,
        options: const TaskOptions(queue: 'emails', maxRetries: 3),
      ),
    );

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
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
      final taskId = await stem.enqueue(
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
    await broker.close();
    await backend.close();
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
