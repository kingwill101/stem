import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:stem/observability.dart';
import 'package:stem/stem.dart';

import 'demo_config.dart';
import 'photo_batch.dart';

enum PhotoQueuePhase {
  queued,
  processing,
  interrupted,
  budgetWaiting,
  waiting,
  completed,
  error,
}

/// Counts only committed photo records, never planned work or elapsed time.
class PhotoQueueStatus {
  const PhotoQueueStatus({
    required this.phase,
    this.total = 0,
    this.completed = 0,
    this.failed = 0,
    this.countsKnown = true,
  });

  factory PhotoQueueStatus.fromJobs(
    List<TaskStatusRecord> jobs,
    PhotoQueuePhase phase,
  ) {
    final batch = PhotoBatchSummary.activeOrLatest(jobs);
    return PhotoQueueStatus(
      phase: phase,
      total: batch?.jobs.length ?? 0,
      completed: batch?.completed ?? 0,
      failed: batch?.failed ?? 0,
    );
  }

  final PhotoQueuePhase phase;
  final int total;
  final int completed;
  final int failed;
  final bool countsKnown;
  bool get ongoing => phase == PhotoQueuePhase.processing;
  String get title => switch (phase) {
    PhotoQueuePhase.queued => 'Photos queued',
    PhotoQueuePhase.processing => 'Processing photos',
    PhotoQueuePhase.interrupted => 'Interrupted work detected',
    PhotoQueuePhase.budgetWaiting => 'Budget reached · waiting for Android',
    PhotoQueuePhase.waiting => 'Waiting for Android',
    PhotoQueuePhase.completed => 'Photo processing completed',
    PhotoQueuePhase.error => 'Photo processing needs attention',
  };
  String get body =>
      '${countsKnown ? '$completed / $total recorded photos finished' : 'Open Photo Lab to inspect persisted work'}'
      '${failed > 0 ? ' · $failed failed / cancelled' : ''}'
      '${phase == PhotoQueuePhase.interrupted ? ' · Recovering a previous attempt; retry policy may defer it' : ''}'
      '${phase == PhotoQueuePhase.waiting || phase == PhotoQueuePhase.budgetWaiting ? ' · More work remains' : ''}';

  PhotoQueueStatus withPhase(PhotoQueuePhase phase) => PhotoQueueStatus(
    phase: phase,
    total: total,
    completed: completed,
    failed: failed,
    countsKnown: countsKnown,
  );
}

/// App-owned, best-effort status surface. Never starts a foreground service.
/// A single ID replaces previous status; only active processing is ongoing.
class AndroidStatusNotifications {
  AndroidStatusNotifications({
    Future<void> Function(PhotoQueueStatus)? show,
    Future<void> Function()? cancel,
  }) : _showOverride = show,
       _cancelOverride = cancel;

  static final instance = AndroidStatusNotifications();
  static const notificationId = 4107;
  final _plugin = FlutterLocalNotificationsPlugin();
  final Future<void> Function(PhotoQueueStatus)? _showOverride;
  final Future<void> Function()? _cancelOverride;
  bool _initialized = false;
  PhotoQueueStatus _last = const PhotoQueueStatus(
    phase: PhotoQueuePhase.queued,
    countsKnown: false,
  );

  Future<void> _initialize() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_photo_status'),
      ),
    );
    _initialized = true;
  }

  /// Call only from an explicit foreground UI action, never the dispatcher.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      await _initialize();
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    } catch (error) {
      stemLogger.warning(
        'Optional notification permission unavailable: $error',
      );
      return false;
    }
  }

  Future<void> show(PhotoQueueStatus status) async {
    _last = status;
    try {
      if (_showOverride != null) {
        await _showOverride(status);
        return;
      }
      if (!Platform.isAndroid) return;
      await _initialize();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.areNotificationsEnabled() != true) return;
      await _plugin.show(
        id: notificationId,
        title: status.title,
        body: status.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'stem_photo_status',
            'Photo processing status',
            channelDescription: 'Status of locally queued photo work',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            onlyAlertOnce: true,
            ongoing: status.ongoing,
            autoCancel: !status.ongoing,
            showProgress: status.total > 0,
            maxProgress: status.total,
            progress: status.completed,
            // Safety expiry if Android destroys Dart before finally runs.
            // This is display expiry, not fabricated processing progress.
            timeoutAfter: status.ongoing ? 120000 : null,
          ),
        ),
      );
    } catch (error) {
      stemLogger.warning('Optional status notification unavailable: $error');
    }
  }

  Future<void> phase(PhotoQueuePhase phase) => show(_last.withPhase(phase));

  Future<void> cancel() async {
    try {
      if (_cancelOverride != null) {
        await _cancelOverride();
      } else if (Platform.isAndroid) {
        await _initialize();
        await _plugin.cancel(id: notificationId);
      }
    } catch (error) {
      stemLogger.warning(
        'Optional status notification cancellation failed: $error',
      );
    }
  }

  Future<PhotoQueueStatus?> read(StemApp app, PhotoQueuePhase phase) async {
    try {
      final jobs = <TaskStatusRecord>[];
      int? offset = 0;
      do {
        final page = await app.backend.listTaskStatuses(
          TaskStatusListRequest(queue: queueName, offset: offset!),
        );
        jobs.addAll(page.items);
        offset = page.nextOffset;
      } while (offset != null);
      return PhotoQueueStatus.fromJobs(jobs, phase);
    } catch (error) {
      stemLogger.warning('Optional notification status read failed: $error');
      return null;
    }
  }

  Future<void> queued(StemApp app) async {
    final status = await read(app, PhotoQueuePhase.queued);
    if (status != null && status.total > status.completed) await show(status);
  }
}

/// Event-triggered reads, serialized and joined before the owning app closes.
/// This observes the existing workers; it neither polls nor consumes anything.
class PhotoQueueNotificationObserver {
  PhotoQueueNotificationObserver(
    this.app,
    this.notifications, {
    Iterable<Worker>? workers,
  }) : _workers = List.unmodifiable((workers ?? [app.worker]).toSet());
  final StemApp app;
  final AndroidStatusNotifications notifications;
  final List<Worker> _workers;
  final List<StreamSubscription<WorkerEvent>> _subscriptions = [];
  final List<SignalSubscription> _interruptions = [];
  Future<void> _pending = Future.value();
  // Retries retain the task ID and may run on another worker. Retain the newest
  // interrupted attempt so unrelated or older terminal events cannot clear it.
  final Map<String, int> _interruptedAttempts = {};

  Future<void> start() async {
    for (final worker in _workers) {
      _interruptions.add(
        StemSignals.onTaskInterrupted((payload, _) {
          // Recovery evidence, not proof of why the previous process stopped.
          final envelope = payload.envelope;
          final previous = _interruptedAttempts[envelope.id];
          if (previous == null || envelope.attempt > previous) {
            _interruptedAttempts[envelope.id] = envelope.attempt;
          }
          return _refresh();
        }, workerId: worker.workerId),
      );
      _subscriptions.add(
        worker.events.listen((event) {
          if (event.type != WorkerEventType.progress &&
              event.type != WorkerEventType.heartbeat) {
            final envelope = event.envelope;
            final terminal =
                event.type == WorkerEventType.completed ||
                event.type == WorkerEventType.failed ||
                event.type == WorkerEventType.revoked;
            if (terminal && envelope != null) {
              final interruptedAttempt = _interruptedAttempts[envelope.id];
              if (interruptedAttempt != null &&
                  envelope.attempt >= interruptedAttempt) {
                _interruptedAttempts.remove(envelope.id);
              }
            }
            unawaited(_refresh());
          }
        }),
      );
    }
    await _refresh();
  }

  Future<void> _refresh() => _pending = _pending.then((_) async {
    final status = await notifications.read(
      app,
      _interruptedAttempts.isNotEmpty
          ? PhotoQueuePhase.interrupted
          : PhotoQueuePhase.processing,
    );
    if (status != null && status.total > status.completed) {
      await notifications.show(status);
    }
  });

  Future<void> finish(WorkerRunOutcome? outcome) async {
    for (final subscription in _interruptions) {
      subscription.cancel();
    }
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await _pending;
    final status = await notifications.read(app, PhotoQueuePhase.completed);
    if (status == null ||
        outcome == null ||
        outcome.reason == WorkerRunStopReason.failed) {
      await notifications.phase(PhotoQueuePhase.error);
    } else if (outcome.reason == WorkerRunStopReason.cancelled ||
        status.total == 0) {
      await notifications.cancel();
    } else {
      await notifications.show(
        status.withPhase(
          status.failed > 0 && status.completed == status.total
              ? PhotoQueuePhase.error
              : status.completed < status.total
              ? outcome.reason == WorkerRunStopReason.budgetExceeded
                    ? PhotoQueuePhase.budgetWaiting
                    : PhotoQueuePhase.waiting
              : PhotoQueuePhase.completed,
        ),
      );
    }
  }
}
