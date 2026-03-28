import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

const _defaultTaskName = 'greeting.send';

const _demoTaskSpecs = <_DemoTaskSpec>[
  _DemoTaskSpec(
    name: 'greeting.send',
    queue: 'greetings',
    namespace: 'customer-experience',
    maxRetries: 5,
  ),
  _DemoTaskSpec(
    name: 'customer.followup',
    queue: 'greetings',
    namespace: 'customer-experience',
    maxRetries: 4,
  ),
  _DemoTaskSpec(
    name: 'billing.charge',
    queue: 'billing',
    namespace: 'revenue',
    maxRetries: 5,
  ),
  _DemoTaskSpec(
    name: 'billing.settlement',
    queue: 'billing',
    namespace: 'revenue',
    maxRetries: 3,
  ),
  _DemoTaskSpec(
    name: 'reports.aggregate',
    queue: 'reporting',
    namespace: 'analytics',
    maxRetries: 2,
  ),
  _DemoTaskSpec(
    name: 'reports.publish',
    queue: 'reporting',
    namespace: 'analytics',
    maxRetries: 2,
  ),
];

final _demoTaskByName = {
  for (final spec in _demoTaskSpecs) spec.name: spec,
};

const _workflowTemplates = <_WorkflowTemplate>[
  _WorkflowTemplate(
    name: 'onboarding.v1',
    steps: [
      _WorkflowStep(taskName: 'greeting.send', stepName: 'prepare-message'),
      _WorkflowStep(taskName: 'billing.charge', stepName: 'charge-account'),
      _WorkflowStep(taskName: 'reports.publish', stepName: 'publish-summary'),
    ],
  ),
  _WorkflowTemplate(
    name: 'billing.closeout',
    steps: [
      _WorkflowStep(taskName: 'billing.charge', stepName: 'capture'),
      _WorkflowStep(taskName: 'billing.settlement', stepName: 'settle'),
      _WorkflowStep(taskName: 'reports.aggregate', stepName: 'rollup'),
    ],
  ),
  _WorkflowTemplate(
    name: 'customer.reengagement',
    steps: [
      _WorkflowStep(taskName: 'customer.followup', stepName: 'hydrate-profile'),
      _WorkflowStep(taskName: 'greeting.send', stepName: 'send-message'),
      _WorkflowStep(taskName: 'reports.publish', stepName: 'write-audit'),
    ],
  ),
];

Future<void> main(List<String> args) async {
  // #region signing-producer-config
  final config = StemConfig.fromEnvironment();
  final observability = ObservabilityConfig.fromEnvironment();
  // #endregion signing-producer-config
  observability.applyMetricExporters();
  observability.applySignalConfiguration();

  final backendUrl = config.resultBackendUrl;
  if (backendUrl == null) {
    throw StateError(
      'STEM_RESULT_BACKEND_URL must be configured for the microservice enqueuer.',
    );
  }
  // #region signing-producer-signer
  final signer = PayloadSigner.maybe(config.signing);
  // #endregion signing-producer-signer
  final httpContext = _buildHttpSecurityContext();

  final tasks = _demoTaskSpecs
      .map<TaskHandler<Object?>>(
        (spec) => FunctionTaskHandler<String>(
          name: spec.name,
          entrypoint: _placeholderEntrypoint,
          options: TaskOptions(queue: spec.queue, maxRetries: spec.maxRetries),
        ),
      )
      .toList(growable: false);

  // #region signing-producer-stem
  final client = await StemClient.fromUrl(
    config.brokerUrl,
    adapters: [StemRedisAdapter(tls: config.tls)],
    overrides: StemStoreOverrides(backend: backendUrl),
    tasks: tasks,
    signer: signer,
  );
  // #endregion signing-producer-stem
  final canvas = client.createCanvas(tasks: tasks);
  final autoFill = _AutoFillController(
    enqueuer: client,
    enabled: _boolFromEnv(
      Platform.environment['ENQUEUER_AUTOFILL_ENABLED'],
      defaultValue: true,
    ),
    interval: Duration(
      milliseconds: _intFromEnv(
        Platform.environment['ENQUEUER_AUTOFILL_INTERVAL_MS'],
        defaultValue: 2500,
      ),
    ),
    batchSize: _intFromEnv(
      Platform.environment['ENQUEUER_AUTOFILL_BATCH_SIZE'],
      defaultValue: 2,
    ),
    failureEvery: _intFromEnv(
      Platform.environment['ENQUEUER_AUTOFILL_FAILURE_EVERY'],
      defaultValue: 8,
    ),
  )..start();

  final router = Router()
    ..post('/enqueue', (Request request) async {
      final body = jsonDecode(await request.readAsString()) as Map;
      final requestedTask = (body['task'] as String?)?.trim();
      final taskName = (requestedTask == null || requestedTask.isEmpty)
          ? _defaultTaskName
          : requestedTask;
      final taskSpec = _demoTaskByName[taskName];
      if (taskSpec == null) {
        return Response(
          HttpStatus.badRequest,
          body: jsonEncode({
            'error': 'Unknown task "$taskName".',
            'knownTasks': _demoTaskSpecs.map((entry) => entry.name).toList(),
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final name = (body['name'] as String?)?.trim();
      final entity = (name == null || name.isEmpty) ? 'friend' : name;
      final taskId = await client.enqueue(
        taskSpec.name,
        args: {
          'name': entity,
          if (body['delayMs'] is num)
            'delayMs': (body['delayMs'] as num).toInt(),
          if (body['fail'] is bool) 'fail': body['fail'] as bool,
        },
        options: TaskOptions(
          queue: taskSpec.queue,
          maxRetries: taskSpec.maxRetries,
        ),
        meta: {
          'namespace': taskSpec.namespace,
          'stem.namespace': taskSpec.namespace,
          'demo.source': 'http.enqueue',
        },
      );
      return Response.ok(
        jsonEncode({'taskId': taskId, 'task': taskSpec.name}),
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
            options: const TaskOptions(queue: 'greetings'),
          ),
      ]);
      await dispatch.dispose();
      final groupId = dispatch.groupId;

      return Response.ok(
        jsonEncode({'groupId': groupId, 'count': names.length}),
        headers: {'content-type': 'application/json'},
      );
    })
    ..get('/group/<groupId>', (Request request, String groupId) async {
      final status = await client.getGroupStatus(groupId);
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
    autoFill.stop();
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

class _AutoFillController {
  _AutoFillController({
    required this.enqueuer,
    required this.enabled,
    required this.interval,
    required this.batchSize,
    required this.failureEvery,
  });

  final TaskEnqueuer enqueuer;
  final bool enabled;
  final Duration interval;
  final int batchSize;
  final int failureEvery;

  Timer? _timer;
  var _tick = 0;
  var _running = false;

  void start() {
    if (!enabled) return;
    stdout.writeln(
      'Auto-fill enabled (interval=${interval.inMilliseconds}ms, '
      'batchSize=$batchSize, failureEvery=$failureEvery).',
    );
    _timer = Timer.periodic(interval, (_) {
      if (_running) return;
      _running = true;
      unawaited(_produce().whenComplete(() => _running = false));
    });
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> _produce() async {
    _tick++;
    for (var index = 0; index < batchSize; index++) {
      final spec = _demoTaskSpecs[(_tick + index) % _demoTaskSpecs.length];
      final shouldFail = failureEvery > 0 &&
          _tick % failureEvery == 0 &&
          index == 0 &&
          (spec.queue == 'greetings' || spec.queue == 'billing');
      final delayMs = 220 + ((_tick + index) % 8) * 160;
      final taskId = await _enqueueTask(
        spec,
        label: 'demo-${_tick.toString().padLeft(4, '0')}-$index',
        delayMs: delayMs,
        shouldFail: shouldFail,
        extraMeta: const {'demo.kind': 'standalone'},
      );
      stdout.writeln(
        'Auto-filled standalone task $taskId '
        '(${spec.name} queue=${spec.queue} delayMs=$delayMs fail=$shouldFail).',
      );
    }

    if (_tick.isEven) {
      await _enqueueWorkflowSample();
    }
  }

  Future<String> _enqueueTask(
    _DemoTaskSpec spec, {
    required String label,
    required int delayMs,
    required bool shouldFail,
    Map<String, Object?> extraMeta = const {},
  }) {
    return enqueuer.enqueue(
      spec.name,
      args: {
        'name': label,
        'delayMs': delayMs,
        if (shouldFail) 'fail': true,
      },
      options: TaskOptions(queue: spec.queue, maxRetries: spec.maxRetries),
      meta: {
        'namespace': spec.namespace,
        'stem.namespace': spec.namespace,
        ...extraMeta,
      },
    );
  }

  Future<void> _enqueueWorkflowSample() async {
    final template = _workflowTemplates[_tick % _workflowTemplates.length];
    final runId = 'wf-${_tick.toString().padLeft(6, '0')}';
    final forceFailure = failureEvery > 0 && _tick % failureEvery == 0;
    for (var index = 0; index < template.steps.length; index++) {
      final step = template.steps[index];
      final spec = _demoTaskByName[step.taskName];
      if (spec == null) {
        continue;
      }
      final shouldFail = forceFailure && index == template.steps.length - 1;
      final delayMs = 280 + ((_tick + index) % 6) * 140;
      final taskId = await _enqueueTask(
        spec,
        label: '$runId-${step.stepName}',
        delayMs: delayMs,
        shouldFail: shouldFail,
        extraMeta: {
          'demo.kind': 'workflow-step',
          'demo.workflow': template.name,
          'stem.workflow.runId': runId,
          'stem.workflow.name': template.name,
          'stem.workflow.step': step.stepName,
          'stem.workflow.stepIndex': index,
          'stem.workflow.iteration': 0,
        },
      );
      stdout.writeln(
        'Auto-filled workflow step $taskId '
        '(run=$runId workflow=${template.name} step=${step.stepName}).',
      );
    }
  }
}

class _DemoTaskSpec {
  const _DemoTaskSpec({
    required this.name,
    required this.queue,
    required this.namespace,
    required this.maxRetries,
  });

  final String name;
  final String queue;
  final String namespace;
  final int maxRetries;
}

class _WorkflowTemplate {
  const _WorkflowTemplate({required this.name, required this.steps});

  final String name;
  final List<_WorkflowStep> steps;
}

class _WorkflowStep {
  const _WorkflowStep({required this.taskName, required this.stepName});

  final String taskName;
  final String stepName;
}

bool _boolFromEnv(String? value, {required bool defaultValue}) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return defaultValue;
  }
  return normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'on';
}

int _intFromEnv(String? value, {required int defaultValue}) {
  final parsed = int.tryParse(value?.trim() ?? '');
  if (parsed == null || parsed <= 0) {
    return defaultValue;
  }
  return parsed;
}
