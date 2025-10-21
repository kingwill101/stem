import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();
  final broker = await RedisStreamsBroker.connect(
    config.brokerUrl,
    tls: config.tls,
  );
  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be configured for the microservice enqueuer.',
    );
  }
  final backend = await RedisResultBackend.connect(
    backendUrl,
    tls: config.tls,
  );
  final signer = PayloadSigner.maybe(config.signing);
  final httpContext = _buildHttpSecurityContext();

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
  final canvas = Canvas(
    broker: broker,
    backend: backend,
    registry: registry,
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
    })
    ..post('/group', (Request request) async {
      final payload = jsonDecode(await request.readAsString()) as Map;
      final names = (payload['names'] as List?)?.cast<String>() ?? const [];
      if (names.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Provide a non-empty "names" array'}),
        );
      }

      final groupId = await canvas.group([
        for (final name in names)
          task(
            'greeting.send',
            args: {'name': name},
            options: const TaskOptions(queue: 'greetings'),
          ),
      ]);

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
    });

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '8081') ?? 8081;
  final server = await serve(
    handler,
    InternetAddress.anyIPv4,
    port,
    securityContext: httpContext,
  );

  final scheme = httpContext != null ? 'https' : 'http';
  stdout.writeln(
    'Enqueue API listening on $scheme://${server.address.address}:$port',
  );

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Shutting down enqueue service ($signal)...');
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

SecurityContext? _buildHttpSecurityContext() {
  final cert = Platform.environment['ENQUEUER_TLS_CERT']?.trim();
  final key = Platform.environment['ENQUEUER_TLS_KEY']?.trim();
  if (cert == null || cert.isEmpty || key == null || key.isEmpty) {
    return null;
  }
  final context = SecurityContext();
  context.useCertificateChain(cert);
  context.usePrivateKey(key);

  final clientCa = Platform.environment['ENQUEUER_TLS_CLIENT_CA']?.trim();
  if (clientCa != null && clientCa.isNotEmpty) {
    context.setTrustedCertificates(clientCa);
  }
  return context;
}
