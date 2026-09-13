import 'dart:async';
import 'dart:io';

import 'package:ormed/ormed.dart';
import 'package:ormed_postgres/ormed_postgres.dart';
import 'package:stem/stem.dart';
import 'package:stem_postgres/orm_registry.g.dart';
import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

void main() {
  final url =
      Platform.environment['STEM_TEST_POSTGRES_URL'] ??
      Platform.environment['POSTGRES_URL'];
  if (url == null || url.isEmpty) {
    test(
      'watcher races require PostgreSQL',
      () {},
      skip: 'Set STEM_TEST_POSTGRES_URL or POSTGRES_URL.',
    );
    return;
  }

  for (final terminal in [
    WorkflowStatus.failed,
    WorkflowStatus.completed,
    WorkflowStatus.cancelled,
  ]) {
    test('a scanned watcher cannot replace $terminal', () async {
      final fixture = await _fixture(url);
      final pending = _resolveAfterScan(fixture);
      await fixture.driver.scanned.future.timeout(const Duration(seconds: 5));

      switch (terminal) {
        case WorkflowStatus.failed:
          expect(
            await fixture.writer.markFailedForExecution(
              fixture.runId,
              executionId: fixture.executionId,
              error: StateError('terminal failure'),
              stack: StackTrace.empty,
            ),
            TerminalFailureResult.applied,
          );
        case WorkflowStatus.completed:
          await fixture.writer.markCompleted(fixture.runId, 'completed');
        case WorkflowStatus.cancelled:
          await fixture.writer.cancel(fixture.runId, reason: 'cancelled');
        case WorkflowStatus.running:
        case WorkflowStatus.suspended:
          throw StateError('Unexpected terminal status');
      }

      fixture.driver.release.complete();
      expect(await pending, isEmpty);
      expect((await fixture.writer.get(fixture.runId))!.status, terminal);

      // An old execution must not recreate a watcher after terminalization.
      await fixture.writer.registerWatcher(fixture.runId, 'late', 'late-topic');
      expect((await fixture.writer.get(fixture.runId))!.status, terminal);
      expect(await fixture.writer.listWatchers('topic'), isEmpty);
      expect(await fixture.writer.listWatchers('late-topic'), isEmpty);
    });
  }

  test('a scanned watcher cannot consume a replacement topic', () async {
    final fixture = await _fixture(url);
    final pending = _resolveAfterScan(fixture);
    await fixture.driver.scanned.future.timeout(const Duration(seconds: 5));
    await fixture.writer.registerWatcher(fixture.runId, 'new', 'other-topic');
    fixture.driver.release.complete();

    expect(await pending, isEmpty);
    final run = (await fixture.writer.get(fixture.runId))!;
    expect(run.status, WorkflowStatus.suspended);
    expect(run.waitTopic, 'other-topic');
    expect(
      (await fixture.writer.listWatchers('other-topic')).single.stepName,
      'new',
    );
  });

  test('same-topic replacement uses the current watcher metadata', () async {
    final fixture = await _fixture(url);
    final pending = _resolveAfterScan(fixture);
    await fixture.driver.scanned.future.timeout(const Duration(seconds: 5));
    await fixture.writer.registerWatcher(
      fixture.runId,
      'new',
      'topic',
      data: const {'generation': 2},
    );
    fixture.driver.release.complete();

    final result = (await pending).single;
    expect(result.stepName, 'new');
    expect(result.resumeData['generation'], 2);
    expect(result.resumeData['payload'], {'event': 'value'});
    expect(await fixture.writer.listWatchers('topic'), isEmpty);
  });
}

typedef _Fixture = ({
  PostgresWorkflowStore writer,
  PostgresWorkflowStore resolver,
  _WatcherScanGate driver,
  String runId,
  String executionId,
});

Future<_Fixture> _fixture(String url) async {
  final namespace = 'watcher_barrier_${DateTime.now().microsecondsSinceEpoch}';
  final writer = await PostgresWorkflowStore.connect(url, namespace: namespace);
  addTearDown(writer.close);
  final driver = _WatcherScanGate(url);
  final source = DataSource(
    DataSourceOptions(
      driver: driver,
      registry: bootstrapOrm(),
      name: namespace,
    ),
  );
  addTearDown(source.dispose);
  final resolver = await PostgresWorkflowStore.fromDataSource(
    source,
    namespace: namespace,
    runMigrations: false,
  );
  addTearDown(resolver.close);
  final runId = await writer.createRun(
    workflow: 'watcher-race',
    params: const {},
  );
  final claim = (await writer.claimRunExecution(runId, ownerId: 'owner'))!;
  await writer.registerWatcher(runId, 'old', 'topic');
  return (
    writer: writer,
    resolver: resolver,
    driver: driver,
    runId: runId,
    executionId: claim.executionId,
  );
}

Future<List<WorkflowWatcherResolution>> _resolveAfterScan(_Fixture fixture) {
  fixture.driver.armed = true;
  final pending = fixture.resolver.resolveWatchers(
    'topic',
    const {'event': 'value'},
  );
  addTearDown(() async {
    if (!fixture.driver.release.isCompleted) fixture.driver.release.complete();
    await pending.timeout(const Duration(seconds: 5));
  });
  return pending;
}

/// Pauses after the candidate SELECT, before the resolver reads the run.
/// Other operations use an independent connection, so their commit happens at a
/// deterministic point without timing sleeps or production test hooks.
class _WatcherScanGate extends PostgresDriverAdapter {
  _WatcherScanGate(String url)
    : super.custom(
        config: DatabaseConfig(driver: 'postgres', options: {'url': url}),
      );

  bool armed = false;
  final scanned = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> execute(QueryPlan plan) async {
    final rows = await super.execute(plan);
    final sql = describeQuery(plan).sql;
    if (armed &&
        sql.contains('stem_workflow_watchers') &&
        !sql.contains('FOR UPDATE')) {
      armed = false;
      scanned.complete();
      await release.future;
    }
    return rows;
  }
}
