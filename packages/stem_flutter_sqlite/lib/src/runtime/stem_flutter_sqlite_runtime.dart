import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';
import 'package:stem_flutter_sqlite/src/runtime/stem_flutter_storage_layout.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

/// Foreground Stem runtime backed by SQLite files resolved for Flutter.
///
/// This runtime opens the SQLite broker and result backend, initializes the
/// Flutter-side dependency bootstrap, and exposes a producer-ready [Stem]
/// instance for enqueueing work from the UI isolate.
class StemFlutterSqliteRuntime {
  StemFlutterSqliteRuntime._({
    required this.layout,
    required this.broker,
    required this.backend,
    required this.stem,
  });

  /// Storage layout used by the runtime.
  final StemFlutterStorageLayout layout;

  /// The broker owned by this runtime.
  final SqliteBroker broker;

  /// The result backend owned by this runtime.
  final SqliteResultBackend backend;

  /// The foreground [Stem] client used to enqueue work.
  final Stem stem;

  /// Opens a foreground runtime using the provided [layout].
  static Future<StemFlutterSqliteRuntime> open({
    required StemFlutterStorageLayout layout,
    required List<TaskHandler<Object?>> tasks,
    Duration brokerVisibilityTimeout = const Duration(seconds: 6),
    Duration brokerPollInterval = const Duration(milliseconds: 250),
    Duration producerSweeperInterval = Duration.zero,
    Duration backendCleanupInterval = const Duration(days: 3650),
  }) async {
    await ensureStemFlutterDependenciesInitialized();
    final broker = await SqliteBroker.open(
      layout.brokerFile,
      defaultVisibilityTimeout: brokerVisibilityTimeout,
      pollInterval: brokerPollInterval,
      sweeperInterval: producerSweeperInterval,
    );
    final backend = await SqliteResultBackend.open(
      layout.backendFile,
      cleanupInterval: backendCleanupInterval,
    );
    final stem = Stem(broker: broker, tasks: tasks);
    return StemFlutterSqliteRuntime._(
      layout: layout,
      broker: broker,
      backend: backend,
      stem: stem,
    );
  }

  /// Closes this runtime and releases all owned resources.
  Future<void> close() async {
    await stem.close();
    await backend.close();
  }
}
