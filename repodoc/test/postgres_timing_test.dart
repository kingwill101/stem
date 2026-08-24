import 'package:repodoc/src/benchmarks/postgres_timing.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

void main() {
  group('PostgresTimingCollector', () {
    test('aggregates operation latency and queue wait', () {
      final collector = PostgresTimingCollector();
      collector
        ..add(
          const PostgresOperationTiming(
            component: 'broker',
            operation: 'broker.publish',
            queueWait: Duration(milliseconds: 1),
            execution: Duration(milliseconds: 2),
            total: Duration(milliseconds: 3),
            succeeded: true,
          ),
        )
        ..add(
          const PostgresOperationTiming(
            component: 'broker',
            operation: 'broker.publish',
            queueWait: Duration(milliseconds: 2),
            execution: Duration(milliseconds: 3),
            total: Duration(milliseconds: 5),
            succeeded: true,
          ),
        )
        ..add(
          const PostgresOperationTiming(
            component: 'broker',
            operation: 'broker.publish',
            queueWait: Duration(milliseconds: 8),
            execution: Duration(milliseconds: 10),
            total: Duration(milliseconds: 18),
            succeeded: false,
            error: 'connection reset',
          ),
        );

      final rows = collector.toJson();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['operation'], equals('broker.publish'));
      expect(row['count'], equals(3));
      expect(row['failures'], equals(1));
      expect(row['avg_ms'], closeTo(26 / 3, 0.001));
      expect(row['p95_ms'], equals(18.0));
      expect(row['max_ms'], equals(18.0));
      expect(row['avg_execution_ms'], closeTo(15 / 3, 0.001));
      expect(row['avg_queue_wait_ms'], closeTo(11 / 3, 0.001));
    });

    test('sorts operations by name', () {
      final collector = PostgresTimingCollector()
        ..add(
          const PostgresOperationTiming(
            component: 'backend',
            operation: 'backend.set',
            queueWait: Duration.zero,
            execution: Duration.zero,
            total: Duration.zero,
            succeeded: true,
          ),
        )
        ..add(
          const PostgresOperationTiming(
            component: 'broker',
            operation: 'broker.publish',
            queueWait: Duration.zero,
            execution: Duration.zero,
            total: Duration.zero,
            succeeded: true,
          ),
        );

      expect(
        collector.toJson().map((row) => row['operation']),
        equals(['backend.set', 'broker.publish']),
      );
    });

    test('aggregates SQL query timings by component and statement', () {
      final collector = PostgresTimingCollector()
        ..addQuery(
          const PostgresQueryTiming(
            component: 'broker',
            sql: 'insert into stem_queue_jobs ...',
            duration: Duration(milliseconds: 4),
            succeeded: true,
          ),
        )
        ..addQuery(
          const PostgresQueryTiming(
            component: 'broker',
            sql: 'insert into stem_queue_jobs ...',
            duration: Duration(milliseconds: 8),
            succeeded: true,
          ),
        )
        ..addQuery(
          const PostgresQueryTiming(
            component: 'backend',
            sql: 'insert into stem_queue_jobs ...',
            duration: Duration(milliseconds: 20),
            succeeded: true,
          ),
        );

      final rows = collector.queryJson();
      expect(rows, hasLength(2));
      expect(rows.first['component'], equals('backend'));
      expect(rows.first['max_ms'], equals(20.0));
      expect(rows.last['count'], equals(2));
      expect(rows.last['avg_ms'], equals(6.0));
    });

    test('bounds SQL groups while retaining aggregate counts', () {
      final collector = PostgresTimingCollector(sampleSize: 2, maxQueryKeys: 1)
        ..addQuery(
          const PostgresQueryTiming(
            component: 'broker',
            sql: 'select old_statement',
            duration: Duration(milliseconds: 1),
            succeeded: true,
          ),
        )
        ..addQuery(
          const PostgresQueryTiming(
            component: 'broker',
            sql: 'select new_statement',
            duration: Duration(milliseconds: 2),
            succeeded: true,
          ),
        )
        ..addQuery(
          const PostgresQueryTiming(
            component: 'broker',
            sql: 'select new_statement',
            duration: Duration(milliseconds: 4),
            succeeded: false,
          ),
        );

      final rows = collector.queryJson();
      expect(rows, hasLength(1));
      expect(rows.single['sql'], equals('select new_statement'));
      expect(rows.single['count'], equals(2));
      expect(rows.single['failures'], equals(1));
      expect(rows.single['max_ms'], equals(4.0));
    });
  });
}
