import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/android_background.dart';
import 'package:stem/stem.dart';

void main() {
  for (final task in [reconciliationTask, workflowWakeupTask]) {
    test('$task delegates only to serial wakeup', () async {
      var requests = 0;
      expect(
        await executeDemoBackgroundTask(
          task,
          isPaused: () async => false,
          requestWakeup: () async {
            requests++;
          },
          runQueue: () => throw StateError('Must not consume from reconciler'),
        ),
        isTrue,
      );
      expect(requests, 1);
    });
  }

  test('workflow wakeup follows due time without tight overdue callbacks', () {
    final now = DateTime.utc(2026);
    expect(
      workflowWakeupDelay(now.add(const Duration(seconds: 10)), now: now),
      const Duration(seconds: 10),
    );
    expect(workflowWakeupDelay(now, now: now), const Duration(seconds: 1));
    expect(
      workflowWakeupDelay(
        now.add(const Duration(milliseconds: 1500)),
        now: now,
      ),
      const Duration(seconds: 2),
    );
    expect(
      workflowWakeupDelay(now.subtract(const Duration(minutes: 1)), now: now),
      const Duration(seconds: 1),
    );
  });

  test('workflow wake registration failure retains native retry', () async {
    expect(
      await executeDemoBackgroundTask(
        queueWakeupTask,
        isPaused: () async => false,
        runQueue: () async =>
            throw WorkflowWakeupRegistrationFailure(StateError('offline')),
      ),
      isFalse,
    );
  });

  for (final reason in WorkerRunStopReason.values) {
    test('drain delegates once and maps ${reason.name}', () async {
      var runs = 0;
      var requests = 0;
      final invocation = executeDemoBackgroundTask(
        queueWakeupTask,
        isPaused: () async => false,
        requestWakeup: () async {
          requests++;
        },
        runQueue: () async {
          runs++;
          return WorkerRunOutcome(
            reason: reason,
            deliveriesProcessed: 2,
            elapsed: const Duration(seconds: 1),
            error: reason == WorkerRunStopReason.failed
                ? StateError('bad configuration')
                : null,
          );
        },
      );
      if (reason == WorkerRunStopReason.failed) {
        await expectLater(invocation, throwsStateError);
      } else {
        expect(await invocation, isTrue);
      }
      expect(runs, 1);
      expect(
        requests,
        reason == WorkerRunStopReason.budgetExceeded ||
                reason == WorkerRunStopReason.idle
            ? 1
            : 0,
      );
    });
  }

  test(
    'budget continuation registration failure retains Android retry',
    () async {
      expect(
        await executeDemoBackgroundTask(
          queueWakeupTask,
          isPaused: () async => false,
          requestWakeup: () => throw StateError('scheduler unavailable'),
          runQueue: () async => WorkerRunOutcome(
            reason: WorkerRunStopReason.budgetExceeded,
            deliveriesProcessed: 2,
            elapsed: const Duration(seconds: 30),
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'empty reconciliation stops instead of scheduling a callback loop',
    () async {
      var requests = 0;
      expect(
        await executeDemoBackgroundTask(
          queueWakeupTask,
          isPaused: () async => false,
          requestWakeup: () async => requests++,
          runQueue: () async => const WorkerRunOutcome(
            reason: WorkerRunStopReason.idle,
            deliveriesProcessed: 0,
            elapsed: Duration.zero,
          ),
        ),
        isTrue,
      );
      expect(requests, 0);
    },
  );

  test(
    'productive idle reconciliation retains retry if scheduling fails',
    () async {
      expect(
        await executeDemoBackgroundTask(
          queueWakeupTask,
          isPaused: () async => false,
          requestWakeup: () async => throw StateError('offline'),
          runQueue: () async => const WorkerRunOutcome(
            reason: WorkerRunStopReason.idle,
            deliveriesProcessed: 3,
            elapsed: Duration.zero,
          ),
        ),
        isFalse,
      );
    },
  );

  test('worker summaries join counts and never hide permanent failures', () {
    final permanent = StateError('bad registration');
    WorkerRunOutcome result(WorkerRunStopReason reason, {Object? error}) =>
        WorkerRunOutcome(
          reason: reason,
          deliveriesProcessed: 2,
          elapsed: const Duration(seconds: 1),
          error: error,
        );
    final summary = summarizeWorkerRuns([
      result(WorkerRunStopReason.idle),
      result(
        WorkerRunStopReason.failed,
        error: const SocketException('offline'),
      ),
      result(WorkerRunStopReason.failed, error: permanent),
    ], const Duration(seconds: 5));
    expect(summary.deliveriesProcessed, 6);
    expect(summary.elapsed, const Duration(seconds: 5));
    expect(summary.reason, WorkerRunStopReason.failed);
    expect(summary.error, same(permanent));
    expect(
      summarizeWorkerRuns([
        result(WorkerRunStopReason.idle),
        result(WorkerRunStopReason.budgetExceeded),
      ], Duration.zero).reason,
      WorkerRunStopReason.budgetExceeded,
    );
    expect(
      summarizeWorkerRuns([
        result(WorkerRunStopReason.budgetExceeded),
        result(WorkerRunStopReason.cancelled),
      ], Duration.zero).reason,
      WorkerRunStopReason.cancelled,
    );
    expect(() => summarizeWorkerRuns([], Duration.zero), throwsArgumentError);
  });

  test('known temporary connection failure requests Android retry', () async {
    expect(
      await executeDemoBackgroundTask(
        queueWakeupTask,
        isPaused: () async => false,
        runQueue: () async => WorkerRunOutcome(
          reason: WorkerRunStopReason.failed,
          deliveriesProcessed: 0,
          elapsed: Duration.zero,
          error: const SocketException('temporarily unavailable'),
        ),
      ),
      isFalse,
    );
  });

  test('unknown callback fails without touching Stem', () async {
    await expectLater(
      executeDemoBackgroundTask(
        'unknown',
        runQueue: () => throw StateError('Must not open app'),
      ),
      throwsArgumentError,
    );
  });

  for (final task in [
    queueWakeupTask,
    reconciliationTask,
    workflowWakeupTask,
  ]) {
    test('paused $task neither consumes nor schedules', () async {
      expect(
        await executeDemoBackgroundTask(
          task,
          isPaused: () async => true,
          runQueue: () => throw StateError('Must not consume'),
          requestWakeup: () => throw StateError('Must not register'),
        ),
        isTrue,
      );
    });
  }
}
