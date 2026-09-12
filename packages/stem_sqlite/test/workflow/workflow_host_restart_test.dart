import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_sqlite/stem_sqlite.dart';
import 'package:test/test.dart';

void main() {
  test('nullable sentinel results survive completed-run reopen', () async {
    final directory = await Directory.systemTemp.createTemp('host-results-');
    final file = File('${directory.path}/workflows.sqlite');
    final hosts = <WorkflowHost>[];
    addTearDown(() async {
      for (final host in hosts.reversed) {
        await host.close();
      }
      await directory.delete(recursive: true);
    });
    var executed = 0;
    var encoded = 0;
    HostedWorkflow<String, String?> definition() =>
        HostedWorkflow<String, String?>(
          name: 'sentinel.restart',
          resultCodec: PayloadCodec<String?>(
            encode: (value) {
              encoded++;
              return {'present': value != null, 'value': value};
            },
            decode: (payload) {
              if (payload is! Map) {
                throw StateError('Expected a sentinel map, not raw null.');
              }
              return payload['present'] == true
                  ? payload['value']! as String
                  : null;
            },
          ),
          run: (_, input) {
            executed++;
            return input == 'null' ? null : input;
          },
        );
    Future<WorkflowHost> open(HostedWorkflow<String, String?> workflow) async {
      final host = await WorkflowHost.create(
        workflows: [workflow],
        createApp: (definitions) => StemWorkflowApp.fromUrl(
          'sqlite://${file.path}',
          adapters: const [StemSqliteAdapter()],
          workflows: definitions,
        ),
      );
      hosts.add(host);
      return host;
    }

    final original = definition();
    final first = await open(original);
    final nullRun = await first.submit(original, 'null');
    final valueRun = await first.submit(original, 'value');
    expect(await nullRun.result, isNull);
    expect(await valueRun.result, 'value');
    await first.close();
    final fresh = definition();
    final reopened = await open(fresh);
    expect(await (await reopened.observe(fresh, nullRun.id)).result, isNull);
    expect(await (await reopened.observe(fresh, valueRun.id)).result, 'value');
    expect(executed, 2);
    expect(encoded, 2);
  });

  test(
    'host reattaches after reopen without repeating completed checkpoints',
    () async {
      final directory = await Directory.systemTemp.createTemp('stem-host-');
      final file = File('${directory.path}/workflows.sqlite');
      final hosts = <WorkflowHost>[];
      addTearDown(() async {
        for (final host in hosts.reversed) {
          await host.close();
        }
        await directory.delete(recursive: true);
      });
      var preparations = 0;
      var completions = 0;
      const approval = WorkflowEventRef<Map<String, Object?>>(
        topic: 'host.restart.approval',
      );

      // A fresh registration reconstructs executable Dart code, not a closure
      // deserialized from the database. Stable names identify checkpoints.
      HostedWorkflow<String, String> definition() =>
          HostedWorkflow<String, String>(
            name: 'host.restart',
            run: (context, input) async {
              final prepared = await context.step('prepare', () {
                preparations++;
                return input.toUpperCase();
              });
              final decision = await context.awaitEvent('approval', approval);
              return context.step('complete', () {
                completions++;
                return '$prepared:${decision['answer']}';
              });
            },
          );

      Future<WorkflowHost> open(HostedWorkflow<String, String> workflow) async {
        final host = await WorkflowHost.create(
          workflows: [workflow],
          createApp: (definitions) => StemWorkflowApp.fromUrl(
            'sqlite://${file.path}',
            adapters: const [StemSqliteAdapter()],
            workflows: definitions,
            pollInterval: const Duration(milliseconds: 10),
            workerConfig: const StemWorkerConfig(
              queue: 'workflow',
              concurrency: 1,
            ),
          ),
        );
        hosts.add(host);
        return host;
      }

      final original = definition();
      final first = await open(original);
      final pending = await first.submit(original, 'persisted input');
      final stoppedObservation = expectLater(pending.result, throwsStateError);
      await pending
          .watch()
          .firstWhere(
            (snapshot) => snapshot.status == WorkflowStatus.suspended,
          )
          .timeout(const Duration(seconds: 10));
      expect(preparations, 1);
      expect(completions, 0);
      await first.close();
      await stoppedObservation;

      final reconstructed = definition();
      expect(identical(original, reconstructed), isFalse);
      final second = await open(reconstructed);
      final resumed = await second.observe(reconstructed, pending.id);
      expect((await resumed.status()).status, WorkflowStatus.suspended);
      await second.emitEvent(approval, {'answer': 'accepted'});
      expect(
        await resumed.result.timeout(const Duration(seconds: 10)),
        'PERSISTED INPUT:accepted',
      );
      expect(preparations, 1);
      expect(completions, 1);
      await second.close();

      // Reattaching to a completed run reads its durable result; it must not
      // enqueue another execution or call either completed checkpoint body.
      final finalDefinition = definition();
      final third = await open(finalDefinition);
      final completed = await third.observe(finalDefinition, pending.id);
      expect(
        await completed.result.timeout(const Duration(seconds: 10)),
        'PERSISTED INPUT:accepted',
      );
      expect((await completed.status()).status, WorkflowStatus.completed);
      expect(preparations, 1);
      expect(completions, 1);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
