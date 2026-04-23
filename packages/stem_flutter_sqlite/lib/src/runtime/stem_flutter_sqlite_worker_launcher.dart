import 'dart:async';

import 'package:flutter/services.dart';
import 'package:stem_flutter/stem_flutter.dart';
import 'package:stem_flutter_sqlite/src/runtime/stem_flutter_sqlite_worker_bootstrap.dart';
import 'package:stem_flutter_sqlite/src/runtime/stem_flutter_storage_layout.dart';

/// Convenience helpers for spawning SQLite-backed Flutter worker isolates.
///
/// This type bridges the generic [StemFlutterWorkerHost] API with the
/// SQLite-specific bootstrap payload used by worker isolates.
abstract final class StemFlutterSqliteWorkerLauncher {
  /// Spawns a worker isolate using the SQLite bootstrap payload.
  static Future<StemFlutterWorkerHost> spawn({
    required FutureOr<void> Function(Map<String, Object?> message) entrypoint,
    required StemFlutterStorageLayout layout,
    required RootIsolateToken rootIsolateToken,
    required Duration brokerPollInterval,
    required Duration brokerSweeperInterval,
    required Duration brokerVisibilityTimeout,
  }) async {
    final dependencyAssets = await preloadStemFlutterDependencyAssets();
    return StemFlutterWorkerHost.spawn<Map<String, Object?>>(
      entrypoint: entrypoint,
      messageBuilder: (sendPort) {
        final bootstrap = StemFlutterSqliteWorkerBootstrap(
          sendPort: sendPort,
          rootIsolateToken: rootIsolateToken,
          brokerPath: layout.brokerFile.path,
          backendPath: layout.backendFile.path,
          timeMachineAssets: dependencyAssets,
          brokerPollInterval: brokerPollInterval,
          brokerSweeperInterval: brokerSweeperInterval,
          brokerVisibilityTimeout: brokerVisibilityTimeout,
        );
        return bootstrap.toMessage();
      },
    );
  }
}
