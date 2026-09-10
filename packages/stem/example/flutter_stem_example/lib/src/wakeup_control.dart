import 'dart:async';

import 'package:sqlite3/sqlite3.dart';

/// Example-owned, cross-isolate scheduling policy, separate from Stem tasks.
///
/// The intent database at [path] contains only short transactions. A separate
/// `$path.effects` database serializes native effects across isolates. This
/// separation lets Cancel persist and callbacks read pause even if a native
/// platform call never completes. File locks are not isolate-safe.
///
/// Busy acquisition yields to the event loop; synchronous busy waits on the UI
/// isolate could deadlock a platform call held by another isolate.
///
/// Intent commits before effects. Effects recheck intent before each call and
/// after completion, repairing a late result to match the latest intent.
/// [effectWait] bounds callers' wait, NOT the underlying native operation or its
/// mutex. A timed-out operation keeps its mutex until real completion; its late
/// error is handled by Future.timeout. Process exit releases SQLite locks.
/// SQLite and Android are not one atomic transaction: process death or a
/// platform failure can leave stale native registrations. Callback admission
/// still respects pause; startup retries repair. An indefinitely hung effect
/// prevents further native effects in that process, not intent changes. A callback
/// already admitted may finish (including native retries); no task is deleted.
class WakeupControl {
  WakeupControl({
    required this.path,
    required this.register,
    required this.cancel,
    this.effectWait = const Duration(seconds: 5),
  });

  final String path;
  final Future<void> Function() register;
  final Future<void> Function() cancel;
  final Duration effectWait;

  Future<T> _locked<T>(
    String databasePath,
    FutureOr<T> Function(Database) action,
  ) async {
    final db = sqlite3.open(databasePath);
    try {
      db.execute('PRAGMA busy_timeout = 0');
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (true) {
        try {
          db.execute('BEGIN IMMEDIATE');
          break;
        } on SqliteException catch (error) {
          if (error.resultCode != 5 && error.resultCode != 6) rethrow;
          if (DateTime.now().isAfter(deadline)) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      try {
        final result = await action(db);
        db.execute('COMMIT');
        return result;
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      db.close();
    }
  }

  bool _paused(Database db) =>
      db
          .select('SELECT paused FROM wakeup_control WHERE id = 1')
          .single['paused'] ==
      1;

  Future<T> _state<T>(T Function(Database) action) => _locked(path, (db) {
    db.execute(
      'CREATE TABLE IF NOT EXISTS wakeup_control '
      '(id INTEGER PRIMARY KEY CHECK (id = 1), paused INTEGER NOT NULL)',
    );
    db.execute(
      'INSERT OR IGNORE INTO wakeup_control (id, paused) VALUES (1, 0)',
    );
    return action(db);
  });

  Future<bool> isPaused() => _state(_paused);

  Future<void> _intent(bool paused) => _state((db) {
    db.execute('UPDATE wakeup_control SET paused = ? WHERE id = 1', [
      paused ? 1 : 0,
    ]);
  });

  /// Startup repairs effects but never resumes explicit cancellation.
  Future<void> reconcile() => _apply();

  /// Automatic periodic/budget continuation never changes user intent.
  Future<void> request() async {
    if (!await isPaused()) await _apply();
  }

  Future<void> _apply() =>
      _locked('$path.effects', (db) async {
        while (true) {
          final paused = await isPaused();
          try {
            await (paused ? cancel() : register());
          } catch (_) {
            // Even a failed old effect must not prevent repairing newer intent.
            if (paused != await isPaused()) continue;
            rethrow;
          }
          if (paused == await isPaused()) return;
        }
      }).timeout(
        effectWait,
        onTimeout: () => throw TimeoutException(
          'Scheduling intent is saved; native effects are still pending. '
          'A saved pause blocks new callback admission, not active Dart work.',
          effectWait,
        ),
      );

  /// Explicit Retry or successfully committed new publication resumes.
  Future<void> resume() async {
    await _intent(false);
    await request();
  }

  Future<void> pause() async {
    await _intent(true);
    await _apply();
  }
}
