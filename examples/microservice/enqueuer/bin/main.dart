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

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'greeting.send',
        entrypoint: _placeholderEntrypoint,
        options: const TaskOptions(queue: 'greetings', maxRetries: 5),
      ),
    );

  final stem = Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    signer: signer,
  );

  final router = Router()
    ..post('/enqueue', (Request request) async {
      final body = jsonDecode(await request.readAsString()) as Map;
      final name = (body['name'] as String?)?.trim();
      if (name == null || name.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing "name" field'}),
        );
      }
      final taskId = await stem.enqueue(
        'greeting.send',
        args: {'name': name},
        options: const TaskOptions(queue: 'greetings'),
      );
      return Response.ok(
        jsonEncode({'taskId': taskId}),
        headers: {'content-type': 'application/json'},
      );
    });

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '8081') ?? 8081;
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Enqueue API listening on http://${server.address.address}:$port',
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Shutting down enqueue service ($signal)...');
    await server.close(force: true);
    await broker.close();
    await backend?.close();
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
