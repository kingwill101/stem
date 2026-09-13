import 'dart:async';
import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

import '../../../../benchmark/stem_workflow_profile.dart';

void main() {
  test('defaults are modest and aliases accept both option syntaxes', () {
    final defaults = WorkflowProfileConfig.fromArgs([]);
    expect(defaults.runs, 100);
    expect(defaults.warmup, 10);
    expect(defaults.steps, 5);
    expect(defaults.concurrency, 1);
    expect(defaults.holdSeconds, 0);
    final config = WorkflowProfileConfig.fromArgs([
      '--tasks=2',
      '--warmup',
      '0',
      '--steps=3',
      '--concurrency',
      '2',
      '--output=result.json',
    ]);
    expect(config.runs, 2);
    expect(config.warmup, 0);
    expect(config.steps, 3);
    expect(config.concurrency, 2);
    expect(config.output, 'result.json');
  });

  test('rejects invalid, missing, duplicate, and unknown arguments', () {
    for (final arguments in [
      ['--runs=0'],
      ['--runs=-1'],
      ['--tasks=nope'],
      ['--warmup=-1'],
      ['--steps=0'],
      ['--concurrency=0'],
      ['--hold-seconds=-1'],
      ['--timeout-seconds=0'],
      ['--runs=1000000001'],
      ['--runs'],
      ['--runs', '--steps=2'],
      ['--runs=1', '--runs=2'],
      ['--runs=1', '--tasks=2'],
      ['--output='],
      ['--output', ' '],
      ['--unknown=1'],
      ['positional'],
    ]) {
      expect(
        () => WorkflowProfileConfig.fromArgs(arguments),
        throwsFormatException,
        reason: arguments.join(' '),
      );
    }
  });

  test('tiny workload completes warmup before measured checkpoints', () async {
    final result = await runWorkflowProfile(
      WorkflowProfileConfig.fromArgs([
        '--runs=2',
        '--warmup=1',
        '--steps=2',
        '--concurrency=2',
        '--timeout-seconds=5',
      ]),
    );
    expect(result['runtime'], 'StemWorkflowApp.inMemory');
    expect(result['resultPollIntervalMs'], 100);
    final warmup = result['warmup']! as Map<String, Object?>;
    final measured = result['measured']! as Map<String, Object?>;
    expect(warmup['completedRuns'], 1);
    expect(warmup['executedCheckpoints'], 2);
    expect(measured['completedRuns'], 2);
    expect(measured['executedCheckpoints'], 4);
    expect(measured['expectedResultPerRun'], 3);
    expect(
      measured['startedTimelineMicros']! as int,
      greaterThanOrEqualTo(warmup['finishedTimelineMicros']! as int),
    );
    expect(
      DateTime.parse(measured['startedAtUtc']! as String).isUtc,
      isTrue,
    );
    expect(() => jsonEncode(result), returnsNormally);
  });

  test('zero warmup still emits a phase and closes its app', () async {
    final result = await runWorkflowProfile(
      WorkflowProfileConfig.fromArgs([
        '--runs=1',
        '--warmup=0',
        '--steps=1',
        '--timeout-seconds=5',
      ]),
    );
    final warmup = result['warmup']! as Map<String, Object?>;
    final measured = result['measured']! as Map<String, Object?>;
    expect(warmup['completedRuns'], 0);
    expect(warmup['executedCheckpoints'], 0);
    expect(measured['completedRuns'], 1);
    expect(measured['executedCheckpoints'], 1);
  });

  test(
    'submission deadline joins a gated start before cleanup',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var starts = 0;
      final subscription = StemSignals.workflowRunStarted.connect((_, _) async {
        starts++;
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      });
      addTearDown(subscription.cancel);

      final profiling = runWorkflowProfile(
        WorkflowProfileConfig.fromArgs([
          '--runs=2',
          '--warmup=0',
          '--steps=1',
          '--timeout-seconds=1',
        ]),
      );
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      // The phase deadline is an observation/admission deadline. Cleanup is
      // deliberately still waiting for the original start future.
      expect(starts, 1);
      release.complete();
      await expectLater(profiling, throwsA(isA<TimeoutException>()));
      expect(starts, 1);
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
