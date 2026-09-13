import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File database;
  final hosts = <WorkflowHost>[];
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('stem-journal-');
    database = File('${directory.path}/workflow.sqlite');
  });
  tearDown(() async {
    for (final host in hosts.reversed) {
      await host.close();
    }
    hosts.clear();
    await directory.delete(recursive: true);
  });

  Future<WorkflowHost> open(HostedDefinition workflow) async {
    final host = await WorkflowHost.create(
      workflows: [workflow],
      createApp: (definitions) => StemWorkflowApp.fromUrl(
        'sqlite://${database.path}',
        adapters: const [StemSqliteAdapter()],
        workflows: definitions,
        pollInterval: const Duration(milliseconds: 20),
      ),
    );
    hosts.add(host);
    return host;
  }

  test('retry attempt and ETA persist across host reconstruction', () async {
    var available = false;
    var attempts = 0;
    var prepared = 0;
    HostedWorkflow<String, String> definition() =>
        HostedWorkflow<String, String>(
          name: 'journal.retry.restart',
          run: (flow, input) async {
            await flow.step('prepare', () => ++prepared);
            return flow.step(
              'operation',
              () {
                attempts++;
                if (!available) throw StateError('service unavailable');
                return input;
              },
              retry: const WorkflowRetryPolicy(
                maxAttempts: 2,
                delay: Duration(seconds: 2),
              ),
            );
          },
        );
    final firstDefinition = definition();
    final first = await open(firstDefinition);
    final run = await first.submit(firstDefinition, 'done');
    await run
        .watch()
        .firstWhere(
          (state) => state.status == WorkflowStatus.suspended,
        )
        .timeout(const Duration(seconds: 5));
    await first.close();
    expect(attempts, 1);
    final inspection = await SqliteWorkflowStore.open(database);
    final entry = (await inspection.readJournal(
      run.id,
      WorkflowJournalKind.step,
      'operation',
    ))!.entry!;
    expect(entry.data['attempts'], 1);
    expect(entry.data['state'], 'waiting');
    expect(
      DateTime.tryParse(entry.data['nextAttemptAt']! as String),
      isNotNull,
    );
    await inspection.close();

    available = true;
    final secondDefinition = definition();
    final second = await open(secondDefinition);
    final restored = await second.observe(secondDefinition, run.id);
    expect(await restored.result.timeout(const Duration(seconds: 10)), 'done');
    expect(attempts, 2);
    expect(prepared, 1);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('cleanup snapshots and completed markers survive reopen', () async {
    var allowA = false;
    var forwardActions = 0;
    final cleanups = <String>[];
    HostedWorkflow<String, String> definition() {
      final undo = HostedCompensation<String>(
        name: 'undo',
        run: (_, value) {
          cleanups.add(value);
          if (value == 'a' && !allowA) throw StateError('cleanup unavailable');
        },
      );
      return HostedWorkflow<String, String>(
        name: 'journal.compensation.restart',
        compensations: [undo],
        run: (flow, _) async {
          await flow.step('a', () {
            forwardActions++;
            return 'a';
          }, compensation: undo);
          await flow.step('b', () {
            forwardActions++;
            return 'b';
          }, compensation: undo);
          return flow.step<String>(
            'fail',
            () => throw StateError('forward failed'),
            retry: const WorkflowRetryPolicy(),
          );
        },
      );
    }

    final firstDefinition = definition();
    final first = await open(firstDefinition);
    final run = await first.submit(firstDefinition, 'input');
    await expectLater(run.result, throwsA(isA<HostedWorkflowFailure>()));
    await _until(() async {
      final records = await run.compensations();
      return records.length == 2 &&
          records.singleWhere((entry) => entry.name == 'a').data['state'] ==
              'exhausted';
    });
    expect(cleanups, ['b', 'a']);
    await first.close();

    allowA = true;
    final secondDefinition = definition();
    final second = await open(secondDefinition);
    final restored = await second.observe(secondDefinition, run.id);
    await restored.retryCompensations(additionalAttempts: 1);
    await _until(
      () async => (await restored.compensations()).every(
        (entry) => entry.data['state'] == 'completed',
      ),
    );
    expect(cleanups, ['b', 'a', 'a']);
    expect(forwardActions, 2);
    expect((await restored.status()).status, WorkflowStatus.failed);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

Future<void> _until(Future<bool> Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!await condition()) {
    if (elapsed.elapsed > const Duration(seconds: 5)) {
      throw TimeoutException('Persistent compensation did not settle.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
