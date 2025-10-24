import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:stem/src/cli/dependencies.dart';
import 'package:stem/src/cli/dlq.dart';
import 'package:stem/src/cli/observer.dart';
import 'package:stem/src/cli/routing.dart';
import 'package:stem/src/cli/schedule.dart';
import 'package:stem/src/cli/utilities.dart';
import 'package:stem/src/cli/worker.dart';

import '../backend/postgres_backend.dart';
import '../backend/redis_backend.dart';
import '../brokers/postgres_broker.dart';
import '../brokers/redis_broker.dart';
import '../core/config.dart';
import '../core/contracts.dart';
import '../control/revoke_store.dart';
import '../routing/routing_registry.dart';
import '../security/tls.dart';

const brokerEnvKey = 'STEM_BROKER_URL';
const backendEnvKey = 'STEM_RESULT_BACKEND_URL';

typedef CliContextBuilder = Future<CliContext> Function();

class StemCommandRunner extends CommandRunner<int> {
  StemCommandRunner({required this.dependencies})
    : super('stem', 'Stem command-line interface') {
    addCommand(ScheduleCommand(dependencies));
    addCommand(ObserveCommand(dependencies));
    addCommand(WorkerCommand(dependencies));
    addCommand(DlqCommand(dependencies));
    addCommand(HealthCommand(dependencies));
    addCommand(RoutingCommand(dependencies));
  }

  final StemCommandDependencies dependencies;

  Future<int> execute(List<String> arguments) async {
    try {
      final result = await run(arguments);
      return result ?? 0;
    } on UsageException catch (e) {
      dependencies.err.writeln(e);
      return 64;
    }
  }
}

Future<int> runStemCli(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  String? scheduleFilePath,
  Future<CliContext> Function()? contextBuilder,
  Map<String, String>? environment,
  ScheduleContextBuilder? scheduleContextBuilder,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final resolvedEnvironment = Map<String, String>.from(
    environment ?? Platform.environment,
  );
  final CliContextBuilder cliContextBuilder =
      contextBuilder ??
      (() => createDefaultContext(environment: resolvedEnvironment));

  final dependencies = StemCommandDependencies(
    out: stdoutSink,
    err: stderrSink,
    environment: resolvedEnvironment,
    scheduleFilePath: scheduleFilePath,
    cliContextBuilder: cliContextBuilder,
    scheduleContextBuilder: scheduleContextBuilder,
  );

  final runner = StemCommandRunner(dependencies: dependencies);
  return runner.execute(arguments);
}

class HealthCommand extends Command<int> {
  HealthCommand(this.dependencies) {
    argParser
      ..addOption(
        'broker',
        help: 'Override broker URL (defaults to STEM_BROKER_URL).',
        valueHelp: 'redis://host:port',
      )
      ..addOption(
        'backend',
        help: 'Override result backend URL.',
        valueHelp: 'redis://host:port',
      )
      ..addFlag(
        'skip-backend',
        defaultsTo: false,
        negatable: false,
        help: 'Skip checking the result backend connection.',
      )
      ..addFlag(
        'allow-insecure',
        defaultsTo: false,
        negatable: false,
        help:
            'Temporarily allow TLS handshakes without certificate validation for debugging.',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        negatable: false,
        help: 'Emit health results as JSON.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'health';

  @override
  final String description = 'Perform broker/backend connectivity checks.';

  @override
  Future<int> run() async => _healthCheck(argResults!);

  Future<int> _healthCheck(ArgResults args) async {
    final out = dependencies.out;
    final err = dependencies.err;
    final environment = dependencies.environment;

    final overrides = Map<String, String>.from(environment);
    final brokerOverride = (args['broker'] as String?)?.trim();
    if (brokerOverride != null && brokerOverride.isNotEmpty) {
      overrides[brokerEnvKey] = brokerOverride;
    }
    final backendOverride = (args['backend'] as String?)?.trim();
    if (backendOverride != null && backendOverride.isNotEmpty) {
      overrides[backendEnvKey] = backendOverride;
    }
    if (args['allow-insecure'] == true) {
      overrides[TlsEnvKeys.allowInsecure] = 'true';
    }

    StemConfig config;
    try {
      config = StemConfig.fromEnvironment(overrides);
    } on Object catch (error) {
      err.writeln('Failed to load StemConfig: $error');
      return 64;
    }

    final results = <_HealthCheckResult>[];
    final brokerUrl = overrides[brokerEnvKey] ?? config.brokerUrl;
    results.add(await _checkBrokerHealth(brokerUrl, config.tls));

    final skipBackend = args['skip-backend'] as bool? ?? false;
    final backendUrl = overrides[backendEnvKey] ?? config.resultBackendUrl;
    if (!skipBackend && backendUrl != null && backendUrl.isNotEmpty) {
      results.add(await _checkBackendHealth(backendUrl, config.tls));
    }

    final jsonOutput = args['json'] as bool? ?? false;
    if (jsonOutput) {
      out.writeln(jsonEncode(results.map((r) => r.toJson()).toList()));
    } else {
      for (final result in results) {
        final prefix = result.success ? '[ok]   ' : '[fail]';
        out.writeln('$prefix ${result.component}: ${result.message}');
        if (!result.success && result.context.isNotEmpty) {
          final tls = result.context['tls'] as Map<String, Object?>?;
          if (tls != null) {
            out.writeln(
              '       TLS -> ca=${tls['caCertificate']}, client=${tls['clientCertificate']}, allowInsecure=${tls['allowInsecure']}',
            );
          }
          final hints = result.context['hints'] as List<String>? ?? const [];
          for (final hint in hints) {
            out.writeln('       hint: $hint');
          }
        }
      }
    }

    final success = results.every((result) => result.success);
    return success ? 0 : 70;
  }

  Future<_HealthCheckResult> _checkBrokerHealth(
    String url,
    TlsConfig tls,
  ) async {
    final uri = Uri.parse(url);
    if (isPostgresScheme(uri.scheme)) {
      try {
        final broker = await PostgresBroker.connect(
          url,
          applicationName: 'stem-cli-health',
          tls: tls,
        );
        await broker.close();
        return _HealthCheckResult(
          component: 'broker',
          success: true,
          message: 'Connected to $url',
        );
      } on SocketException catch (error) {
        return _HealthCheckResult(
          component: 'broker',
          success: false,
          message: 'Connection failed for $url: $error',
        );
      } on Object catch (error) {
        return _HealthCheckResult(
          component: 'broker',
          success: false,
          message: 'Connection failed for $url: $error',
        );
      }
    }

    try {
      final broker = await RedisStreamsBroker.connect(
        url,
        tls: tls,
        blockTime: const Duration(seconds: 1),
      );
      await broker.close();
      return _HealthCheckResult(
        component: 'broker',
        success: true,
        message: 'Connected to $url',
      );
    } on HandshakeException catch (error) {
      return _HealthCheckResult(
        component: 'broker',
        success: false,
        message: 'TLS handshake failed for $url: $error',
        context: _tlsFailureContext(tls),
      );
    } on Object catch (error) {
      return _HealthCheckResult(
        component: 'broker',
        success: false,
        message: 'Connection failed for $url: $error',
      );
    }
  }

  Future<_HealthCheckResult> _checkBackendHealth(
    String url,
    TlsConfig tls,
  ) async {
    final uri = Uri.parse(url);
    if (isPostgresScheme(uri.scheme)) {
      try {
        final backend = await PostgresResultBackend.connect(
          url,
          applicationName: 'stem-cli-health',
          tls: tls,
        );
        await backend.close();
        return _HealthCheckResult(
          component: 'backend',
          success: true,
          message: 'Connected to $url',
        );
      } on Object catch (error) {
        return _HealthCheckResult(
          component: 'backend',
          success: false,
          message: 'Connection failed for $url: $error',
        );
      }
    }

    try {
      final backend = await RedisResultBackend.connect(url, tls: tls);
      await backend.close();
      return _HealthCheckResult(
        component: 'backend',
        success: true,
        message: 'Connected to $url',
      );
    } on HandshakeException catch (error) {
      return _HealthCheckResult(
        component: 'backend',
        success: false,
        message: 'TLS handshake failed for $url: $error',
        context: _tlsFailureContext(tls),
      );
    } on Object catch (error) {
      return _HealthCheckResult(
        component: 'backend',
        success: false,
        message: 'Connection failed for $url: $error',
      );
    }
  }

  Map<String, Object?> _tlsFailureContext(TlsConfig tls) => {
    'tls': {
      'caCertificate': tls.caCertificateFile ?? 'system',
      'clientCertificate': tls.clientCertificateFile ?? 'not provided',
      'allowInsecure': tls.allowInsecure,
    },
    'hints': tls.allowInsecure
        ? const [
            'TLS verification is disabled (STEM_TLS_ALLOW_INSECURE=true); ensure this is intentional.',
          ]
        : const [
            'Verify certificate paths or temporarily set STEM_TLS_ALLOW_INSECURE=true to bypass validation while debugging.',
          ],
  };
}

class _HealthCheckResult {
  _HealthCheckResult({
    required this.component,
    required this.success,
    required this.message,
    Map<String, Object?>? context,
  }) : context = context ?? const {};

  final String component;
  final bool success;
  final String message;
  final Map<String, Object?> context;

  Map<String, Object?> toJson() => {
    'component': component,
    'status': success ? 'ok' : 'error',
    'message': message,
    if (context.isNotEmpty) 'context': context,
  };
}

class CliContext {
  CliContext({
    required this.broker,
    this.backend,
    this.revokeStore,
    required this.routing,
    required this.dispose,
  });

  final Broker broker;
  final ResultBackend? backend;
  final RevokeStore? revokeStore;
  final RoutingRegistry routing;
  final Future<void> Function() dispose;
}
