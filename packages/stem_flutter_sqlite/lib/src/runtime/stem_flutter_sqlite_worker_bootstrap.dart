import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
// ignore: implementation_imports, reason: First-party adapter uses internal Flutter bootstrap helpers without exposing them publicly.
import 'package:stem_flutter/src/runtime/stem_flutter_dependency_bootstrap.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

/// Serializable bootstrap payload for a Flutter SQLite worker isolate.
///
/// This payload contains the file paths and dependency assets needed to reopen
/// SQLite stores inside a background isolate.
class StemFlutterSqliteWorkerBootstrap {
  /// Creates a worker bootstrap payload.
  const StemFlutterSqliteWorkerBootstrap({
    required this.sendPort,
    required this.rootIsolateToken,
    required this.brokerPath,
    required this.backendPath,
    required this.timeMachineAssets,
    required this.brokerPollInterval,
    required this.brokerSweeperInterval,
    required this.brokerVisibilityTimeout,
  });

  /// Decodes an isolate-safe message into a strongly-typed payload.
  factory StemFlutterSqliteWorkerBootstrap.fromMessage(
    Map<Object?, Object?> message,
  ) {
    return StemFlutterSqliteWorkerBootstrap(
      sendPort: message['sendPort']! as SendPort,
      rootIsolateToken: message['rootIsolateToken']! as RootIsolateToken,
      brokerPath: message['brokerPath']! as String,
      backendPath: message['backendPath']! as String,
      timeMachineAssets:
          (message['timeMachineAssets']! as Map<Object?, Object?>)
              .cast<String, Uint8List>(),
      brokerPollInterval: Duration(
        milliseconds: message['brokerPollIntervalMs']! as int,
      ),
      brokerSweeperInterval: Duration(
        milliseconds: message['brokerSweeperIntervalMs']! as int,
      ),
      brokerVisibilityTimeout: Duration(
        milliseconds: message['brokerVisibilityTimeoutMs']! as int,
      ),
    );
  }

  /// The signal port owned by the UI isolate.
  final SendPort sendPort;

  /// The root isolate token required by Flutter background isolates.
  final RootIsolateToken rootIsolateToken;

  /// The path to the broker SQLite file.
  final String brokerPath;

  /// The path to the backend SQLite file.
  final String backendPath;

  /// The preloaded `time_machine2` binary assets.
  final Map<String, Uint8List> timeMachineAssets;

  /// The poll interval used by the worker broker.
  final Duration brokerPollInterval;

  /// The sweeper interval used by the worker broker.
  final Duration brokerSweeperInterval;

  /// The default visibility timeout used by the worker broker.
  final Duration brokerVisibilityTimeout;

  /// Encodes this payload into an isolate-safe message.
  Map<String, Object?> toMessage() => <String, Object?>{
    'sendPort': sendPort,
    'rootIsolateToken': rootIsolateToken,
    'brokerPath': brokerPath,
    'backendPath': backendPath,
    'timeMachineAssets': timeMachineAssets,
    'brokerPollIntervalMs': brokerPollInterval.inMilliseconds,
    'brokerSweeperIntervalMs': brokerSweeperInterval.inMilliseconds,
    'brokerVisibilityTimeoutMs': brokerVisibilityTimeout.inMilliseconds,
  };

  /// Prepares Flutter platform channels and dependencies in the isolate.
  Future<void> initializeBackgroundDependencies() async {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
    await initializeStemFlutterBackgroundDependencies(timeMachineAssets);
  }
}

/// SQLite stores opened inside a Flutter worker isolate.
class StemFlutterSqliteWorkerStores {
  StemFlutterSqliteWorkerStores._({
    required this.broker,
    required this.backend,
  });

  /// The broker used by the worker isolate.
  final SqliteBroker broker;

  /// The result backend used by the worker isolate.
  final SqliteResultBackend backend;

  /// Opens worker stores from a bootstrap payload.
  static Future<StemFlutterSqliteWorkerStores> open(
    StemFlutterSqliteWorkerBootstrap bootstrap,
  ) async {
    final broker = await SqliteBroker.open(
      File(bootstrap.brokerPath),
      defaultVisibilityTimeout: bootstrap.brokerVisibilityTimeout,
      pollInterval: bootstrap.brokerPollInterval,
      sweeperInterval: bootstrap.brokerSweeperInterval,
    );
    final backend = await SqliteResultBackend.open(File(bootstrap.backendPath));
    return StemFlutterSqliteWorkerStores._(broker: broker, backend: backend);
  }

  /// Closes all opened stores.
  Future<void> close() async {
    await backend.close();
    await broker.close();
  }
}
