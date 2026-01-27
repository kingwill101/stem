import 'dart:async';
import 'dart:io';

import 'package:artisanal/artisanal.dart';
import 'package:stem/stem.dart';
import 'package:stem_cli/src/cli/cli_runner.dart';
import 'package:stem_cli/src/cli/schedule.dart';
// import 'package:stem_cloud_worker/stem_cloud_worker.dart';
import 'package:stem_redis/stem_redis.dart';

import 'file_schedule_repository.dart';
import 'utilities.dart';
import 'workflow_context.dart';

typedef ScheduleContextBuilder = Future<ScheduleCliContext> Function();
typedef WorkflowContextBuilder = Future<WorkflowCliContext> Function();

class StemCommandDependencies {
  StemCommandDependencies({
    required this.out,
    required this.err,
    required this.environment,
    required this.scheduleFilePath,
    required CliContextBuilder cliContextBuilder,
    ScheduleContextBuilder? scheduleContextBuilder,
    WorkflowContextBuilder? workflowContextBuilder,
  }) : console = Console(
         out: (line) => out.writeln(line),
         err: (line) => err.writeln(line),
         interactive: stdin.hasTerminal,
       ),
       _cliContextBuilder = cliContextBuilder,
       _scheduleContextBuilder = scheduleContextBuilder,
       _workflowContextBuilder = workflowContextBuilder;

  final StringSink out;
  final StringSink err;
  final Console console;
  final Map<String, String> environment;
  final String? scheduleFilePath;

  final CliContextBuilder _cliContextBuilder;
  final ScheduleContextBuilder? _scheduleContextBuilder;
  final WorkflowContextBuilder? _workflowContextBuilder;

  Future<CliContext> createCliContext() => _cliContextBuilder();

  Future<ScheduleCliContext> createScheduleContext() {
    if (_scheduleContextBuilder != null) {
      return _scheduleContextBuilder();
    }
    return _createScheduleCliContext(
      repoPath: scheduleFilePath,
      environment: environment,
    );
  }

  Future<WorkflowCliContext> createWorkflowContext() {
    final builder = _workflowContextBuilder;
    if (builder != null) {
      return builder();
    }
    return createDefaultWorkflowContext(environment: environment);
  }
}

Future<ScheduleCliContext> _createScheduleCliContext({
  String? repoPath,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final url = env['STEM_SCHEDULE_STORE_URL']?.trim();
  final tls = TlsConfig.fromEnvironment(env);
  if (url == null || url.isEmpty) {
    return ScheduleCliContext.file(
      repo: FileScheduleRepository(path: repoPath),
    );
  }

  final uri = Uri.parse(url);
  final disposables = <Future<void> Function()>[];
  ScheduleStore store;
  switch (uri.scheme) {
    case 'redis':
    case 'rediss':
      final redisStore = await RedisScheduleStore.connect(url, tls: tls);
      store = redisStore;
      disposables.add(() => redisStore.close());
      break;
    case 'http':
    case 'https':
    // final apiKey = resolveStemCloudApiKey(env);
    // final namespace = resolveStemCloudNamespace(env);
    // final cloudStore = StemCloudScheduleStore.connect(
    //   apiBase: uri,
    //   apiKey: apiKey,
    //   namespace: namespace,
    // );
    // store = cloudStore;
    // disposables.add(() => cloudStore.close());
    // break;
    case 'memory':
      store = InMemoryScheduleStore();
      break;
    default:
      throw StateError('Unsupported schedule store scheme: ${uri.scheme}');
  }

  return ScheduleCliContext.store(
    storeInstance: store,
    dispose: () async {
      for (final disposer in disposables.reversed) {
        await disposer();
      }
    },
  );
}
