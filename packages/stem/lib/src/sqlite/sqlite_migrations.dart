import 'package:sqlite3/sqlite3.dart';

/// Utilities that create and maintain SQLite schema objects used by the
/// Stem broker and result backend implementations.
///
/// These helpers are intentionally idempotent so they can run on every startup.
/// Callers are expected to open the [Database] with `journal_mode=WAL` and
/// `synchronous=NORMAL` (or stricter) to avoid long-lived writer locks while
/// keeping durability guarantees. See `doc/internal/operations/sqlite.md` for
/// additional operational guidance.
class SqliteMigrations {
  const SqliteMigrations._();

  /// Ensures that queue storage tables exist for the SQLite broker.
  static void ensureBrokerTables(
    Database db, {
    String namespace = 'stem',
  }) {
    final jobs = _tableName(namespace, 'queue_jobs');
    final deadLetters = _tableName(namespace, 'dead_letters');

    db.execute('''
CREATE TABLE IF NOT EXISTS $jobs (
  id TEXT PRIMARY KEY,
  queue TEXT NOT NULL,
  envelope TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 0,
  max_retries INTEGER NOT NULL DEFAULT 0,
  priority INTEGER NOT NULL DEFAULT 0,
  not_before INTEGER,
  locked_at INTEGER,
  locked_until INTEGER,
  locked_by TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS ${jobs}_queue_priority_idx
  ON $jobs(queue, priority DESC, created_at)
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS ${jobs}_not_before_idx
  ON $jobs(not_before)
''');

    db.execute('''
CREATE TABLE IF NOT EXISTS $deadLetters (
  id TEXT PRIMARY KEY,
  queue TEXT NOT NULL,
  envelope TEXT NOT NULL,
  reason TEXT,
  meta TEXT,
  dead_at INTEGER NOT NULL
)
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS ${deadLetters}_queue_dead_at_idx
  ON $deadLetters(queue, dead_at DESC)
''');
  }

  /// Ensures that result backend tables exist for the SQLite backend.
  static void ensureResultTables(
    Database db, {
    String namespace = 'stem',
  }) {
    final taskResults = _tableName(namespace, 'task_results');
    final groups = _tableName(namespace, 'groups');
    final groupResults = _tableName(namespace, 'group_results');
    final workerHeartbeats = _tableName(namespace, 'worker_heartbeats');

    db.execute('''
CREATE TABLE IF NOT EXISTS $taskResults (
  id TEXT PRIMARY KEY,
  state TEXT NOT NULL,
  payload TEXT,
  error TEXT,
  attempt INTEGER NOT NULL DEFAULT 0,
  meta TEXT NOT NULL DEFAULT '{}',
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS ${taskResults}_expires_at_idx
  ON $taskResults(expires_at)
''');

    db.execute('''
CREATE TABLE IF NOT EXISTS $groups (
  id TEXT PRIMARY KEY,
  expected INTEGER NOT NULL,
  meta TEXT NOT NULL DEFAULT '{}',
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
)
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS ${groups}_expires_at_idx
  ON $groups(expires_at)
''');

    db.execute('''
CREATE TABLE IF NOT EXISTS $groupResults (
  group_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  state TEXT NOT NULL,
  payload TEXT,
  error TEXT,
  attempt INTEGER NOT NULL DEFAULT 0,
  meta TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  PRIMARY KEY (group_id, task_id),
  FOREIGN KEY (group_id) REFERENCES $groups(id) ON DELETE CASCADE
)
''');

    db.execute('''
CREATE TABLE IF NOT EXISTS $workerHeartbeats (
  worker_id TEXT PRIMARY KEY,
  namespace TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  isolate_count INTEGER NOT NULL,
  inflight INTEGER NOT NULL,
  queues TEXT NOT NULL DEFAULT '[]',
  last_lease_renewal INTEGER,
  version TEXT NOT NULL,
  extras TEXT NOT NULL DEFAULT '{}',
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
)
''');

    db.execute('''
CREATE INDEX IF NOT EXISTS ${workerHeartbeats}_expires_at_idx
  ON $workerHeartbeats(expires_at)
''');
  }

  static String _tableName(String namespace, String table) {
    return namespace.isEmpty ? table : '${namespace}_$table';
  }
}
