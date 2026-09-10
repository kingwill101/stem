import 'dart:io';

import 'package:stem/observability.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';
import 'package:workmanager/workmanager.dart';

import 'android_status_notifications.dart';
import 'demo_workers.dart';
import 'demo_workflows.dart';
import 'wakeup_control.dart';

const queueWakeupTask = 'stem.demo.drain';
const reconciliationTask = 'stem.demo.reconcile';
const workflowWakeupTask = 'stem.demo.workflow-wakeup';
const _uniqueDrain = 'stem.demo.serial-drain';
const _uniqueWorkflowWakeup = 'stem.demo.next-workflow-wakeup';

/// App-owned policy: all drain requests join one serial native work chain.
///
/// In workmanager_android 0.9.3 UPDATE maps to APPEND_OR_REPLACE, not KEEP.
/// A request arriving while a drain finishes therefore gets a successor.
Future<void> _registerDrain() => Workmanager().registerOneOffTask(
  _uniqueDrain,
  queueWakeupTask,
  existingWorkPolicy: ExistingWorkPolicy.update,
  backoffPolicy: BackoffPolicy.exponential,
  backoffPolicyDelay: const Duration(seconds: 30),
);

/// Register reconciliation before requesting a drain. Periodic callbacks only
/// schedule this same serial chain; they never consume concurrently with it.
Future<void> _registerWakeups() async {
  await Workmanager().registerPeriodicTask(
    reconciliationTask,
    reconciliationTask,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
  await _registerDrain();
}

/// Cancel only this demo's registrations, not other application work.
/// Native cancellation is not a Dart task-abort or durable queue deletion.
Future<void> _cancelNativeWakeups() async {
  await Workmanager().cancelByUniqueName(reconciliationTask);
  await Workmanager().cancelByUniqueName(_uniqueWorkflowWakeup);
  await Workmanager().cancelByUniqueName(_uniqueDrain);
  await AndroidStatusNotifications.instance.cancel();
}

Future<WakeupControl> _control({Future<void> Function()? register}) async {
  final layout = await StemFlutterStorageLayout.applicationSupport();
  return WakeupControl(
    path: '${layout.root.path}${Platform.pathSeparator}wakeup-control.sqlite',
    register: register ?? _registerWakeups,
    cancel: _cancelNativeWakeups,
  );
}

Future<void> requestQueueWakeup() async => (await _control()).request();
Future<void> reconcileQueueWakeups() async => (await _control()).reconcile();
Future<void> resumeQueueWakeups() async => (await _control()).resume();
Future<void> cancelQueueWakeups() async => (await _control()).pause();
Future<bool> queueWakeupsPaused() async => (await _control()).isPaused();

/// A timed scheduler callback only appends to the serial drain chain. It never
/// executes a workflow concurrently with that chain. Android may run it later.
Future<void> requestWorkflowWakeup(DateTime dueAt) async {
  final control = await _control(
    register: () => Workmanager().registerOneOffTask(
      _uniqueWorkflowWakeup,
      workflowWakeupTask,
      initialDelay: workflowWakeupDelay(dueAt),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    ),
  );
  await control.request();
}

Duration workflowWakeupDelay(DateTime dueAt, {DateTime? now}) {
  final delay = dueAt.difference(now ?? DateTime.now());
  // Avoid tight callback chains if a persisted deadline is already overdue.
  // Workmanager's Android binding uses whole seconds. Round upward rather than
  // waking before the durable deadline and creating an unnecessary idle drain.
  return Duration(
    seconds: delay <= const Duration(seconds: 1)
        ? 1
        : (delay.inMicroseconds / Duration.microsecondsPerSecond).ceil(),
  );
}

class WorkflowWakeupRegistrationFailure implements Exception {
  WorkflowWakeupRegistrationFailure(this.cause);
  final Object cause;

  @override
  String toString() => 'Could not register workflow continuation: $cause';
}

/// Each callback hosts ordinary Stem workers with their own subscriptions.
/// All core run futures and observer reads finish before any owned stores close.
Future<WorkerRunOutcome> runDemoQueue() async {
  final primary = await createDemoWorker(demoWorkerSpecs.first);
  final workers = <DemoWorkerRuntime>[primary];
  PhotoQueueNotificationObserver? observer;
  WorkerRunOutcome? outcome;
  try {
    workers.addAll(await createAdditionalDemoWorkers());
    for (final worker in workers) {
      await worker.prepareBounded();
    }
    observer = PhotoQueueNotificationObserver(
      primary.app,
      AndroidStatusNotifications.instance,
      workers: workers.map((worker) => worker.app.worker),
    );
    await observer.start();
    final clock = Stopwatch()..start();
    final results = await Future.wait(
      workers.map(
        (worker) => worker.runUntilIdle(
          budget: const Duration(seconds: 30),
          shutdownReserve: const Duration(seconds: 5),
          idleTimeout: const Duration(seconds: 1),
        ),
      ),
    );
    clock.stop();
    for (var i = 0; i < workers.length; i++) {
      stemLogger.info(
        'Stem worker invocation completed',
        fields: {
          'worker': workers[i].spec.id,
          'queues': workers[i].spec.queues,
          'reason': results[i].reason.name,
          'deliveriesProcessed': results[i].deliveriesProcessed,
        },
      );
    }
    outcome = summarizeWorkerRuns(results, clock.elapsed);
    if (outcome.reason == WorkerRunStopReason.idle) {
      final next = await earliestWorkflowWakeAt(primary.workflows!);
      if (next != null) {
        try {
          await requestWorkflowWakeup(next);
        } catch (error) {
          throw WorkflowWakeupRegistrationFailure(error);
        }
      }
    }
    return outcome;
  } finally {
    try {
      await observer?.finish(outcome);
    } finally {
      await Future.wait(workers.map((worker) => worker.close()));
    }
  }
}

/// Combines results after every independent core runner has drained.
/// An idle result is not a global proof that all queues are empty.
WorkerRunOutcome summarizeWorkerRuns(
  List<WorkerRunOutcome> results,
  Duration elapsed,
) {
  if (results.isEmpty) throw ArgumentError('At least one worker is required.');
  final failures = results
      .where((result) => result.reason == WorkerRunStopReason.failed)
      .toList();
  final failure = failures.isEmpty
      ? null
      : failures.firstWhere(
          (result) => result.error is! SocketException,
          orElse: () => failures.first,
        );
  final reasons = results.map((result) => result.reason).toSet();
  return WorkerRunOutcome(
    reason: failure != null
        ? WorkerRunStopReason.failed
        : reasons.contains(WorkerRunStopReason.cancelled)
        ? WorkerRunStopReason.cancelled
        : reasons.contains(WorkerRunStopReason.budgetExceeded)
        ? WorkerRunStopReason.budgetExceeded
        : WorkerRunStopReason.idle,
    deliveriesProcessed: results.fold(
      0,
      (total, result) => total + result.deliveriesProcessed,
    ),
    elapsed: elapsed,
    error: failure?.error,
    stackTrace: failure?.stackTrace,
  );
}

Future<bool> _scheduleSuccessor(Future<void> Function() requestWakeup) async {
  try {
    await requestWakeup();
    return true;
  } catch (error) {
    stemLogger.warning('Could not schedule worker continuation: $error');
    await AndroidStatusNotifications.instance.phase(PhotoQueuePhase.error);
    return false;
  }
}

/// Injection here tests callback routing, not a replacement Stem worker loop.
Future<bool> executeDemoBackgroundTask(
  String task, {
  Future<WorkerRunOutcome> Function() runQueue = runDemoQueue,
  Future<void> Function() requestWakeup = requestQueueWakeup,
  Future<bool> Function() isPaused = queueWakeupsPaused,
}) async {
  if (task != reconciliationTask &&
      task != queueWakeupTask &&
      task != workflowWakeupTask) {
    throw ArgumentError.value(task, 'task', 'Unknown background task');
  }
  // Admission, not task abortion. A cancellation after this check may allow
  // this invocation to finish, but its continuation rechecks durable intent.
  if (await isPaused()) return true;
  if (task == reconciliationTask || task == workflowWakeupTask) {
    await requestWakeup();
    return true;
  }
  stemLogger.info('Android queue invocation starting');
  final WorkerRunOutcome outcome;
  try {
    outcome = await runQueue();
  } on WorkflowWakeupRegistrationFailure catch (error) {
    stemLogger.warning('$error');
    await AndroidStatusNotifications.instance.phase(PhotoQueuePhase.error);
    return false;
  } catch (_) {
    // Includes bootstrap/disposal failures before an observer can report them.
    await AndroidStatusNotifications.instance.phase(PhotoQueuePhase.error);
    rethrow;
  }
  stemLogger.info(
    'Android queue invocation completed',
    fields: {
      'reason': outcome.reason.name,
      'deliveriesProcessed': outcome.deliveriesProcessed,
    },
  );
  switch (outcome.reason) {
    case WorkerRunStopReason.idle:
      // Independent workers can become idle at different times. A productive
      // callback gets one fresh reconciliation pass, covering work published to
      // another queue after that queue's worker stopped. This schedules a normal
      // callback; it is not another consumer loop or a substitute for core drain.
      return outcome.deliveriesProcessed == 0
          ? true
          : _scheduleSuccessor(requestWakeup);
    case WorkerRunStopReason.cancelled:
      return true;
    case WorkerRunStopReason.budgetExceeded:
      // A normal budget boundary is not a transient failure. Append a serial
      // successor before completing this invocation so backoff does not block
      // the chain. A failed registration must retain the native retry.
      return _scheduleSuccessor(requestWakeup);
    case WorkerRunStopReason.failed:
      // No blanket retry of configuration/programming errors. Only known
      // temporary OS/network failures are retried; logs retain other failures.
      if (outcome.error is SocketException) return false;
      Error.throwWithStackTrace(
        outcome.error ?? StateError('Stem queue invocation failed'),
        outcome.stackTrace ?? StackTrace.current,
      );
  }
}
