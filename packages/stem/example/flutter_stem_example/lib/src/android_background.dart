import 'dart:io';

import 'package:stem/observability.dart';
import 'package:stem_flutter_sqlite/stem_flutter_sqlite.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'android_status_notifications.dart';
import 'wakeup_control.dart';

const queueWakeupTask = 'stem.demo.drain';
const reconciliationTask = 'stem.demo.reconcile';
const _uniqueDrain = 'stem.demo.serial-drain';

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
  await Workmanager().cancelByUniqueName(_uniqueDrain);
  await AndroidStatusNotifications.instance.cancel();
}

Future<WakeupControl> _control() async {
  final layout = await StemFlutterStorageLayout.applicationSupport();
  return WakeupControl(
    path: '${layout.root.path}${Platform.pathSeparator}wakeup-control.sqlite',
    register: _registerWakeups,
    cancel: _cancelNativeWakeups,
  );
}

Future<void> requestQueueWakeup() async => (await _control()).request();
Future<void> reconcileQueueWakeups() async => (await _control()).reconcile();
Future<void> resumeQueueWakeups() async => (await _control()).resume();
Future<void> cancelQueueWakeups() async => (await _control()).pause();
Future<bool> queueWakeupsPaused() async => (await _control()).isPaused();

/// Each invocation opens its own handles using exactly the UI's module/layout.
/// The core worker runner owns shutdown; this host joins notification reads
/// before closing the app's stores (the app runner would close them too early).
Future<WorkerRunOutcome> runDemoQueue() async {
  final app = await createDemoApp();
  final observer = PhotoQueueNotificationObserver(
    app,
    AndroidStatusNotifications.instance,
  );
  WorkerRunOutcome? outcome;
  try {
    await observer.start();
    return outcome = await app.worker.runUntilIdle(
      budget: const Duration(seconds: 30),
      shutdownReserve: const Duration(seconds: 5),
      idleTimeout: const Duration(seconds: 1),
    );
  } finally {
    try {
      await observer.finish(outcome);
    } finally {
      await app.close();
    }
  }
}

/// Injection here tests callback routing, not a replacement Stem worker loop.
Future<bool> executeDemoBackgroundTask(
  String task, {
  Future<WorkerRunOutcome> Function() runQueue = runDemoQueue,
  Future<void> Function() requestWakeup = requestQueueWakeup,
  Future<bool> Function() isPaused = queueWakeupsPaused,
}) async {
  if (task != reconciliationTask && task != queueWakeupTask) {
    throw ArgumentError.value(task, 'task', 'Unknown background task');
  }
  // Admission, not task abortion. A cancellation after this check may allow
  // this invocation to finish, but its continuation rechecks durable intent.
  if (await isPaused()) return true;
  if (task == reconciliationTask) {
    await requestWakeup();
    return true;
  }
  stemLogger.info('Android queue invocation starting');
  final WorkerRunOutcome outcome;
  try {
    outcome = await runQueue();
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
    case WorkerRunStopReason.cancelled:
      return true;
    case WorkerRunStopReason.budgetExceeded:
      // A normal budget boundary is not a transient failure. Append a serial
      // successor before completing this invocation so backoff does not block
      // the chain. A failed registration must retain the native retry.
      try {
        await requestWakeup();
        return true;
      } catch (error) {
        stemLogger.warning('Could not schedule budget continuation: $error');
        await AndroidStatusNotifications.instance.phase(PhotoQueuePhase.error);
        return false;
      }
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
