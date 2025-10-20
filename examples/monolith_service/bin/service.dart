import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final broker = InMemoryRedisBroker();
  final backend = InMemoryResultBackend();
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'greeting.send',
        entrypoint: _greetingEntrypoint,
        options: const TaskOptions(
          maxRetries: 3,
          softTimeLimit: Duration(seconds: 5),
          hardTimeLimit: Duration(seconds: 8),
        ),
      ),
    );

  final stem = Stem(broker: broker, registry: registry, backend: backend);
  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    consumerName: 'monolith-worker',
    concurrency: 2,
  );

  await worker.start();
  stdout.writeln('Worker started (concurrency=2).');

  final router = Router()
    ..post('/enqueue', (Request request) async {
      final payload = jsonDecode(await request.readAsString()) as Map;
      final name = (payload['name'] as String?)?.trim();
      if (name == null || name.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing "name" field'}),
        );
      }
      final taskId = await stem.enqueue('greeting.send', args: {'name': name});
      return Response.ok(
        jsonEncode({'taskId': taskId}),
        headers: {'content-type': 'application/json'},
      );
    })
    ..get('/status/<taskId>', (Request request, String taskId) async {
      final status = await backend.get(taskId);
      if (status == null) {
        return Response.notFound(jsonEncode({'error': 'Unknown task'}));
      }
      return Response.ok(
        jsonEncode(status.toJson()),
        headers: {'content-type': 'application/json'},
      );
    });

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  final server = await serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
      'HTTP server listening on http://${server.address.address}:$port');

  void handleShutdown(ProcessSignal signal) async {
    stdout.writeln('Received $signal, shutting down...');
    await worker.shutdown();
    await server.close(force: true);
    broker.dispose();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(handleShutdown);
  ProcessSignal.sigterm.watch().listen(handleShutdown);
}

FutureOr<Object?> _greetingEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final name = (args['name'] as String?) ?? 'friend';
  context.heartbeat();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  context.progress(1.0, data: {'message': 'Greeting sent'});
  stdout.writeln(
    '👋 processed greeting for $name (attempt ${context.attempt})',
  );
  return 'Hello $name!';
}
