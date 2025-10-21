import 'postgres_client.dart';

class PostgresMigrations {
  PostgresMigrations(this._client);

  final PostgresClient _client;

  Future<void> ensureQueueTables() async {
    await _client.run((conn) async {
      await conn.execute('''
CREATE TABLE IF NOT EXISTS stem_jobs (
  id TEXT PRIMARY KEY,
  queue TEXT NOT NULL,
  envelope JSONB NOT NULL,
  attempt INTEGER NOT NULL,
  max_retries INTEGER,
  priority INTEGER NOT NULL DEFAULT 0,
  not_before TIMESTAMPTZ,
  locked_until TIMESTAMPTZ,
  locked_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
''');
      await conn.execute(
        'ALTER TABLE stem_jobs ADD COLUMN IF NOT EXISTS priority INTEGER NOT NULL DEFAULT 0',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS stem_jobs_queue_idx ON stem_jobs (queue, not_before)',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS stem_jobs_priority_idx ON stem_jobs (queue, priority DESC, created_at)',
      );
      await conn.execute('''
CREATE TABLE IF NOT EXISTS stem_jobs_dead (
  id TEXT PRIMARY KEY,
  queue TEXT NOT NULL,
  envelope JSONB NOT NULL,
  reason TEXT NOT NULL,
  meta JSONB,
  dead_lettered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
''');
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS stem_jobs_dead_queue_idx ON stem_jobs_dead (queue, dead_lettered_at DESC)',
      );
    });
  }

  Future<void> ensureResultTables() async {
    await _client.run((conn) async {
      await conn.execute('''
CREATE TABLE IF NOT EXISTS stem_results (
  id TEXT PRIMARY KEY,
  state TEXT NOT NULL,
  payload JSONB,
  error JSONB,
  attempt INTEGER,
  meta JSONB,
  expires_at TIMESTAMPTZ
)
''');
      await conn.execute('''
CREATE TABLE IF NOT EXISTS stem_groups (
  id TEXT PRIMARY KEY,
  expected INTEGER NOT NULL,
  meta JSONB,
  expires_at TIMESTAMPTZ
)
''');
      await conn.execute('''
CREATE TABLE IF NOT EXISTS stem_group_results (
  group_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  status JSONB NOT NULL,
  PRIMARY KEY (group_id, task_id),
  FOREIGN KEY (group_id) REFERENCES stem_groups(id) ON DELETE CASCADE
)
''');
      await conn.execute('''
CREATE TABLE IF NOT EXISTS stem_worker_heartbeats (
  worker_id TEXT PRIMARY KEY,
  heartbeat JSONB NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
)
''');
    });
  }
}
