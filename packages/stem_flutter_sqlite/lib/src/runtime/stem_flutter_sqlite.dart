import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';
import 'package:stem_flutter_sqlite/src/runtime/stem_flutter_storage_layout.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:time_machine2/time_machine2.dart' as tm;

/// Shared SQLite configuration for a local Stem application.
///
/// Producer and worker use the same stores, so namespace, retention, and
/// maintenance settings cannot diverge between independently opened runtimes.
/// Defaults match the underlying SQLite adapter.
class StemFlutterSqliteConfig {
  /// Creates a SQLite configuration.
  const StemFlutterSqliteConfig({
    this.namespace = 'stem',
    this.visibilityTimeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 250),
    this.sweeperInterval = const Duration(seconds: 10),
    this.deadLetterRetention = const Duration(days: 7),
    this.resultTtl = const Duration(days: 1),
    this.groupTtl = const Duration(days: 1),
    this.heartbeatTtl = const Duration(seconds: 60),
    this.cleanupInterval = const Duration(minutes: 1),
  });

  /// Namespace shared by the broker and result backend.
  final String namespace;

  /// Lease duration before interrupted deliveries become eligible for recovery.
  final Duration visibilityTimeout;

  /// Interval between broker reads when no work is available.
  final Duration pollInterval;

  /// Interval for recovering expired leases and maintaining the broker.
  final Duration sweeperInterval;

  /// Retention for dead-lettered deliveries.
  final Duration deadLetterRetention;

  /// Default task-result retention.
  final Duration resultTtl;

  /// Default group-result retention.
  final Duration groupTtl;

  /// Worker heartbeat retention.
  final Duration heartbeatTtl;

  /// Interval for removing expired backend records.
  final Duration cleanupInterval;
}

/// Local SQLite bootstrap returning the ordinary [StemApp].
abstract final class StemFlutterSqlite {
  static Future<void>? _initialization;

  /// Prepares Flutter dependencies before opening Ormed-backed stores.
  ///
  /// [createApp] calls this automatically. Call it explicitly before manually
  /// wrapping an Ormed data source with the core SQLite adapters.
  ///
  /// Ormed initializes Carbonized, whose timezone setup requires Flutter's
  /// asset bundle. This is an adapter dependency, not Stem task initialization.
  static Future<void> initialize() {
    WidgetsFlutterBinding.ensureInitialized();
    return _initialization ??= _initializeOrmedDependencies();
  }

  static Future<void> _initializeOrmedDependencies() async {
    try {
      await tm.TimeMachine.initialize(<String, dynamic>{
        'rootBundle': rootBundle,
      });
    } on Object {
      _initialization = null;
      rethrow;
    }
  }

  /// Creates a durable local app without starting its worker.
  ///
  /// Omit [layout] to use the application support directory. Task definitions,
  /// modules, worker configuration, typed calls, and results use core APIs.
  /// `app.start()` begins consumption; `app.shutdown()` closes the worker and
  /// both stores. The app should normally be owned above individual screens.
  ///
  /// Persistence survives application restarts, not arbitrary side effects:
  /// interrupted tasks can be delivered again after their lease expires.
  /// Handlers should therefore be idempotent. This is not an OS scheduler.
  static Future<StemApp> createApp({
    StemFlutterStorageLayout? layout,
    StemFlutterSqliteConfig storage = const StemFlutterSqliteConfig(),
    StemModule? module,
    Iterable<StemModule> modules = const [],
    Iterable<TaskHandler<Object?>> tasks = const [],
    TaskRegistry? registry,
    StemWorkerConfig workerConfig = StemFlutter.defaultWorkerConfig,
    RevokeStore? revokeStore,
    UniqueTaskCoordinator? uniqueTaskCoordinator,
    RetryStrategy? retryStrategy,
    Iterable<Middleware> middleware = const [],
    PayloadSigner? signer,
    RoutingRegistry? routing,
    TaskPayloadEncoderRegistry? encoderRegistry,
    TaskPayloadEncoder resultEncoder = const JsonTaskPayloadEncoder(),
    TaskPayloadEncoder argsEncoder = const JsonTaskPayloadEncoder(),
    Iterable<TaskPayloadEncoder> additionalEncoders = const [],
  }) async {
    await initialize();
    final resolvedLayout =
        layout ?? await StemFlutterStorageLayout.applicationSupport();
    return StemFlutter.createApp(
      module: module,
      modules: modules,
      tasks: tasks,
      registry: registry,
      broker: StemBrokerFactory(
        create: () => SqliteBroker.open(
          resolvedLayout.brokerFile,
          namespace: storage.namespace,
          defaultVisibilityTimeout: storage.visibilityTimeout,
          pollInterval: storage.pollInterval,
          sweeperInterval: storage.sweeperInterval,
          deadLetterRetention: storage.deadLetterRetention,
        ),
        dispose: (broker) => broker.close(),
      ),
      backend: StemBackendFactory(
        create: () => SqliteResultBackend.open(
          resolvedLayout.backendFile,
          namespace: storage.namespace,
          defaultTtl: storage.resultTtl,
          groupDefaultTtl: storage.groupTtl,
          heartbeatTtl: storage.heartbeatTtl,
          cleanupInterval: storage.cleanupInterval,
        ),
        dispose: (backend) => backend.close(),
      ),
      workerConfig: workerConfig,
      revokeStore: revokeStore,
      uniqueTaskCoordinator: uniqueTaskCoordinator,
      retryStrategy: retryStrategy,
      middleware: middleware,
      signer: signer,
      routing: routing,
      encoderRegistry: encoderRegistry,
      resultEncoder: resultEncoder,
      argsEncoder: argsEncoder,
      additionalEncoders: additionalEncoders,
    );
  }
}
