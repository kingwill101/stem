import 'dart:io';

import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

import 'postgres_timing.dart';

enum ThroughputStore {
  memory,
  sqlite,
  postgres,
  redis;

  static ThroughputStore parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'memory' => memory,
      'sqlite' => sqlite,
      'postgres' || 'postgresql' => postgres,
      'redis' => redis,
      _ => throw ArgumentError(
        'Unsupported benchmark store "$value". '
        'Expected memory, sqlite, postgres, or redis.',
      ),
    };
  }
}

final class ThroughputStoreResources {
  ThroughputStoreResources({
    required this.broker,
    required this.backend,
    this.workerBroker,
    this.workerBackend,
    this.temporaryDatabase,
    this.postgresTimings,
  });

  final QueueBroker broker;
  final ResultBackend backend;
  final QueueBroker? workerBroker;
  final ResultBackend? workerBackend;
  final File? temporaryDatabase;
  final PostgresTimingCollector? postgresTimings;

  QueueBroker get executionBroker => workerBroker ?? broker;

  ResultBackend get executionBackend => workerBackend ?? backend;

  Future<void> close() async {
    try {
      await backend.close();
    } finally {
      try {
        if (workerBackend != null && !identical(workerBackend, backend)) {
          await workerBackend!.close();
        }
      } finally {
        try {
          await broker.close();
        } finally {
          if (workerBroker != null && !identical(workerBroker, broker)) {
            await workerBroker!.close();
          }
          final database = temporaryDatabase;
          if (database != null && database.existsSync()) {
            await database.delete();
          }
        }
      }
    }
  }
}

Future<ThroughputStoreResources> openThroughputStore({
  required ThroughputStore store,
  required String namespace,
  String? postgresUrl,
  String? redisUrl,
  String? sqlitePath,
  PostgresTimingCollector? postgresTimings,
  void Function(String message)? log,
}) async {
  switch (store) {
    case ThroughputStore.memory:
      log?.call('opening in-memory broker and result backend');
      return ThroughputStoreResources(
        broker: InMemoryBroker(namespace: namespace),
        backend: InMemoryResultBackend(),
      );
    case ThroughputStore.sqlite:
      final database = File(
        sqlitePath ??
            '${Directory.current.path}/.tmp/benchmarks/$namespace.sqlite',
      ).absolute;
      await database.parent.create(recursive: true);
      log?.call('opening SQLite broker at ${database.path}');
      final broker = await SqliteBroker.open(
        database,
        namespace: namespace,
        pollInterval: const Duration(milliseconds: 5),
        sweeperInterval: const Duration(hours: 1),
      );
      log?.call('SQLite broker ready; opening result backend');
      try {
        final backend = await SqliteResultBackend.open(
          database,
          namespace: namespace,
          cleanupInterval: const Duration(hours: 1),
        );
        log?.call('SQLite result backend ready');
        return ThroughputStoreResources(
          broker: broker,
          backend: backend,
          temporaryDatabase: sqlitePath == null ? database : null,
        );
      } on Object catch (error, stackTrace) {
        log?.call('SQLite result backend failed; closing broker');
        try {
          await broker.close();
        } on Object catch (closeError) {
          log?.call('failed to close SQLite broker: $closeError');
        }
        if (sqlitePath == null && database.existsSync()) {
          try {
            await database.delete();
          } on Object catch (deleteError) {
            log?.call(
              'failed to delete temporary SQLite database: $deleteError',
            );
          }
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    case ThroughputStore.postgres:
      final url = postgresUrl;
      if (url == null || url.isEmpty) {
        throw ArgumentError(
          'A PostgreSQL URL is required for --store postgres.',
        );
      }
      log?.call('connecting PostgreSQL broker at $url');
      final broker = await PostgresBroker.connect(
        url,
        namespace: namespace,
        pollInterval: const Duration(milliseconds: 100),
        sweeperInterval: const Duration(hours: 1),
        timingListener: postgresTimings?.add,
        queryTimingListener: postgresTimings?.addQuery,
      );
      log?.call('PostgreSQL broker ready; connecting result backend');
      PostgresResultBackend? backend;
      PostgresBroker? workerBroker;
      PostgresResultBackend? workerBackend;
      try {
        backend = await PostgresResultBackend.connect(
          connectionString: url,
          namespace: namespace,
          timingListener: postgresTimings?.add,
          queryTimingListener: postgresTimings?.addQuery,
        );
        log?.call('PostgreSQL result backend ready');
        log?.call('connecting PostgreSQL worker broker');
        workerBroker = await PostgresBroker.connect(
          url,
          namespace: namespace,
          pollInterval: const Duration(milliseconds: 100),
          sweeperInterval: const Duration(hours: 1),
          separateConsumerConnection: true,
          timingListener: postgresTimings?.add,
          queryTimingListener: postgresTimings?.addQuery,
        );
        log?.call('PostgreSQL worker broker ready; connecting worker backend');
        workerBackend = await PostgresResultBackend.connect(
          connectionString: url,
          namespace: namespace,
          timingListener: postgresTimings?.add,
          queryTimingListener: postgresTimings?.addQuery,
        );
        log?.call('PostgreSQL worker backend ready');
        return ThroughputStoreResources(
          broker: broker,
          backend: backend,
          workerBroker: workerBroker,
          workerBackend: workerBackend,
          postgresTimings: postgresTimings,
        );
      } on Object {
        log?.call('PostgreSQL worker resources failed; closing resources');
        for (final close in <Future<void> Function()?>[
          workerBackend?.close,
          workerBroker?.close,
          backend?.close,
          broker.close,
        ]) {
          if (close == null) continue;
          try {
            await close();
          } on Object catch (closeError) {
            log?.call('failed to close PostgreSQL resource: $closeError');
          }
        }
        rethrow;
      }
    case ThroughputStore.redis:
      final url = redisUrl;
      if (url == null || url.isEmpty) {
        throw ArgumentError('A Redis URL is required for --store redis.');
      }
      log?.call('connecting Redis broker at $url');
      final broker = await RedisStreamsBroker.connect(
        url,
        namespace: namespace,
        blockTime: const Duration(milliseconds: 100),
        claimInterval: const Duration(hours: 1),
      );
      log?.call('Redis broker ready; connecting result backend');
      try {
        final backend = await RedisResultBackend.connect(
          url,
          namespace: namespace,
        );
        log?.call('Redis result backend ready');
        return ThroughputStoreResources(broker: broker, backend: backend);
      } on Object catch (error, stackTrace) {
        log?.call('Redis result backend failed; closing broker');
        try {
          await broker.close();
        } on Object catch (closeError) {
          log?.call('failed to close Redis broker: $closeError');
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
  }
}
