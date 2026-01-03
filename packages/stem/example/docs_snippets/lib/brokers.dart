import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:stem_sqlite/stem_sqlite.dart';

// #region brokers-redis
Future<RedisStreamsBroker> connectRedisBroker() {
  return RedisStreamsBroker.connect('redis://127.0.0.1:6379/0');
}
// #endregion brokers-redis

// #region brokers-postgres
Future<PostgresBroker> connectPostgresBroker() {
  return PostgresBroker.connect('postgres://localhost:5432/stem');
}
// #endregion brokers-postgres

// #region brokers-sqlite
Future<SqliteBroker> connectSqliteBroker() {
  final file = File('stem_broker.sqlite');
  return SqliteBroker.open(file);
}
// #endregion brokers-sqlite

// #region brokers-in-memory
InMemoryBroker createInMemoryBroker() {
  return InMemoryBroker();
}

// #endregion brokers-in-memory
