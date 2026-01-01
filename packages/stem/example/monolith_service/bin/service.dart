import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final broker = InMemoryBroker();
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
  final canvas = Canvas(
    broker: broker,
    backend: backend,
    registry: registry,
  );
  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    consumerName: 'monolith-worker',
    concurrency: 2,
  );
  final scheduleStore = InMemoryScheduleStore();
  final beat = Beat(
    store: scheduleStore,
    broker: broker,
    lockStore: InMemoryLockStore(),
    tickInterval: const Duration(seconds: 1),
  );

  await worker.start();
  stdout.writeln('Worker started (concurrency=2).');

  await scheduleStore.upsert(
    ScheduleEntry(
      id: 'demo-greeting',
      taskName: 'greeting.send',
      queue: 'default',
      spec: IntervalScheduleSpec(every: const Duration(seconds: 30)),
      args: const {'name': 'scheduled friend'},
    ),
  );
  await beat.start();
  stdout.writeln('Beat started (schedule demo-greeting every 30s).');

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
    ..post('/group', (Request request) async {
      final payload = jsonDecode(await request.readAsString()) as Map;
      final names = (payload['names'] as List?)?.cast<String>() ?? const [];
      if (names.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Provide a non-empty "names" array'}),
        );
      }
      final dispatch = await canvas.group<Object?>([
        for (final name in names)
          task(
            'greeting.send',
            args: {'name': name},
          )
      ]);
      await dispatch.dispose();
      final groupId = dispatch.groupId;
      return Response.ok(
        jsonEncode({'groupId': groupId, 'count': names.length}),
        headers: {'content-type': 'application/json'},
      );
    })
    ..get('/group/<groupId>', (Request request, String groupId) async {
      final status = await backend.getGroup(groupId);
      if (status == null) {
        return Response.notFound(
          jsonEncode({'error': 'Unknown group or expired results'}),
        );
      }
      return Response.ok(
        jsonEncode({
          'id': status.id,
          'expected': status.expected,
          'completed': status.results.length,
          'results': status.results.map((key, value) => MapEntry(
                key,
                {
                  'state': value.state.name,
                  'attempt': value.attempt,
                  'meta': value.meta,
                },
              )),
        }),
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
    await beat.stop();
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
