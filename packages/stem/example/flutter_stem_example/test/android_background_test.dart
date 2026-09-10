import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/android_background.dart';
import 'package:stem/stem.dart';

void main() {
  test('reconciliation delegates only to serial wakeup', () async {
    var requests = 0;
    expect(
      await executeDemoBackgroundTask(
        reconciliationTask,
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
      expect(requests, reason == WorkerRunStopReason.budgetExceeded ? 1 : 0);
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

  for (final task in [queueWakeupTask, reconciliationTask]) {
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
