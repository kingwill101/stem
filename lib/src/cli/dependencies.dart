import 'dart:async';
import 'dart:io';

import 'package:stem/src/cli/cli_runner.dart';
import 'package:stem/src/cli/schedule.dart';

import '../core/contracts.dart';
import '../security/tls.dart';
import '../scheduler/in_memory_schedule_store.dart';
import '../scheduler/redis_schedule_store.dart';
import 'file_schedule_repository.dart';

typedef ScheduleContextBuilder = Future<ScheduleCliContext> Function();

class StemCommandDependencies {
  StemCommandDependencies({
    required this.out,
    required this.err,
    required this.environment,
    required this.scheduleFilePath,
    required CliContextBuilder cliContextBuilder,
    ScheduleContextBuilder? scheduleContextBuilder,
  })  : _cliContextBuilder = cliContextBuilder,
        _scheduleContextBuilder = scheduleContextBuilder;

  final StringSink out;
  final StringSink err;
  final Map<String, String> environment;
  final String? scheduleFilePath;

  final CliContextBuilder _cliContextBuilder;
  final ScheduleContextBuilder? _scheduleContextBuilder;

  Future<CliContext> createCliContext() => _cliContextBuilder();

  Future<ScheduleCliContext> createScheduleContext() {
    if (_scheduleContextBuilder != null) {
      return _scheduleContextBuilder!();
    }
    return _createScheduleCliContext(
      repoPath: scheduleFilePath,
      environment: environment,
    );
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
