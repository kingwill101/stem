import 'dart:io';

import 'package:args/args.dart';
import 'package:stem/stem.dart';
import 'package:stem_cli/src/cli/cli_runner.dart';
import 'package:stem_cli/src/cli/revoke_store_factory.dart';
import 'package:stem_cli/src/cli/subscription_loader.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';

Duration? parseOptionalDuration(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d+)(ms|s|m|h)$').firstMatch(value.trim());
  if (match == null) return null;
  final number = int.parse(match.group(1)!);
  switch (match.group(2)) {
    case 'ms':
      return Duration(milliseconds: number);
    case 's':
      return Duration(seconds: number);
    case 'm':
      return Duration(minutes: number);
    case 'h':
      return Duration(hours: number);
  }
  return null;
}

Future<CliContext> createDefaultContext({
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final config = StemConfig.fromEnvironment(env);
  final routingRegistry = _loadRoutingRegistry(config);
  final brokerUri = Uri.parse(config.brokerUrl);
  final disposables = <Future<void> Function()>[];
  late Broker broker;
  if (brokerUri.scheme == 'redis' || brokerUri.scheme == 'rediss') {
    final redisBroker = await RedisStreamsBroker.connect(
      config.brokerUrl,
      tls: config.tls,
    );
    broker = redisBroker;
    disposables.add(() => redisBroker.close());
  } else if (isPostgresScheme(brokerUri.scheme)) {
    final postgresBroker = await PostgresBroker.connect(
      config.brokerUrl,
      applicationName: 'stem-cli',
      tls: config.tls,
    );
    broker = postgresBroker;
    disposables.add(() => postgresBroker.close());
  } else if (brokerUri.scheme == 'memory') {
    final inMemory = InMemoryBroker();
    broker = inMemory;
    disposables.add(() async => inMemory.dispose());
  } else {
    throw StateError('Unsupported broker scheme: ${brokerUri.scheme}');
  }

  ResultBackend? backend;
  final backendUrl = config.resultBackendUrl;
  if (backendUrl != null) {
    final backendUri = Uri.parse(backendUrl);
    if (backendUri.scheme == 'redis' || backendUri.scheme == 'rediss') {
      final redisBackend = await RedisResultBackend.connect(
        backendUrl,
        tls: config.tls,
      );
      backend = redisBackend;
      disposables.add(() => redisBackend.close());
    } else if (isPostgresScheme(backendUri.scheme)) {
      final postgresBackend = await PostgresResultBackend.connect(
        backendUrl,
        namespace: 'stem',
        applicationName: 'stem-cli',
        tls: config.tls,
      );
      backend = postgresBackend;
      disposables.add(() => postgresBackend.close());
    } else if (backendUri.scheme == 'memory') {
      backend = InMemoryResultBackend();
    } else {
      throw StateError(
        'Unsupported result backend scheme: ${backendUri.scheme}',
      );
    }
  }

  RevokeStore? revokeStore;
  try {
    revokeStore = await RevokeStoreFactory.create(
      config: config,
      namespace: 'stem',
    );
    disposables.add(() => revokeStore!.close());
  } catch (error) {
    for (final disposer in disposables.reversed) {
      await disposer();
    }
    rethrow;
  }

  return CliContext(
    broker: broker,
    backend: backend,
    revokeStore: revokeStore,
    routing: routingRegistry,
    dispose: () async {
      for (final disposer in disposables.reversed) {
        await disposer();
      }
    },
  );
}

RoutingRegistry _loadRoutingRegistry(StemConfig config) {
  final loader = RoutingConfigLoader(
    StemRoutingContext(
      defaultQueue: config.defaultQueue,
      configPath: config.routingConfigPath,
    ),
  );
  return loader.load();
}

String formatDateTime(DateTime? value) => value?.toIso8601String() ?? '-';
String formatDuration(Duration? value) =>
    value != null ? '${value.inMilliseconds}ms' : '-';

bool isPostgresScheme(String scheme) {
  switch (scheme) {
    case 'postgres':
    case 'postgresql':
    case 'postgresql+ssl':
    case 'postgres+ssl':
      return true;
    default:
      return false;
  }
}

int? parseIntWithDefault(
  String? value,
  String option,
  StringSink err, {
  required int fallback,
  int min = 0,
}) {
  if (value == null) return fallback;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < min) {
    err.writeln('Invalid --$option value: $value');
    return null;
  }
  return parsed;
}

int? parseOptionalInt(
  String? value,
  String option,
  StringSink err, {
  int min = 0,
}) {
  if (value == null) return null;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < min) {
    err.writeln('Invalid --$option value: $value');
    return null;
  }
  return parsed;
}

DateTime? parseIsoTimestamp(String? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value);
  } catch (_) {
    return null;
  }
}

String padCell(String value, int width, {bool alignRight = false}) {
  if (width <= 0) return '';
  var truncated = value;
  if (truncated.length > width) {
    truncated = width <= 3
        ? truncated.substring(0, width)
        : '${truncated.substring(0, width - 3)}...';
  }
  return alignRight ? truncated.padLeft(width) : truncated.padRight(width);
}

String? readQueueArg(ArgResults args, StringSink err) {
  final queue = (args['queue'] as String?)?.trim();
  if (queue == null || queue.isEmpty) {
    err.writeln('Missing required --queue option.');
    return null;
  }
  return queue;
}

String formatReadableDuration(Duration duration) {
  if (duration.inSeconds == 0) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inMinutes >= 1) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return seconds == 0 ? '${minutes}m' : '${minutes}m${seconds}s';
  }
  return '${duration.inSeconds}s';
}
