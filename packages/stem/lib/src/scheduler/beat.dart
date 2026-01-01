import 'dart:async';
import 'dart:math';

import 'package:contextual/contextual.dart';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';
import 'package:stem/src/observability/logging.dart';
import 'package:stem/src/observability/metrics.dart';
import 'package:stem/src/security/signing.dart';
import 'package:stem/src/signals/emitter.dart';

/// Scheduler loop that dispatches due [ScheduleEntry] records.
class Beat {
  /// Creates a scheduler instance with the provided dependencies.
  Beat({
    required this.store,
    required this.broker,
    this.lockStore,
    this.tickInterval = const Duration(seconds: 1),
    this.lockTtl = const Duration(seconds: 5),
    this.signer,
    Random? random,
  }) : _random = random ?? Random();

  /// Schedule store used to fetch due entries.
  final ScheduleStore store;

  /// Broker used to publish scheduled tasks.
  final Broker broker;

  /// Optional lock store for distributed scheduling.
  final LockStore? lockStore;

  /// Interval between polling ticks.
  final Duration tickInterval;

  /// TTL used for schedule locks.
  final Duration lockTtl;

  /// Optional envelope signer for scheduled tasks.
  final PayloadSigner? signer;

  final Random _random;
  static const StemSignalEmitter _signals = StemSignalEmitter(
    defaultSender: 'beat',
  );

  Timer? _timer;
  bool _running = false;

  /// Starts the periodic scheduling loop.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  /// Stops the periodic scheduling loop.
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Runs a single scheduling tick.
  Future<void> runOnce() => _tick();

  Future<void> _tick() async {
    if (!_running && _timer != null) return;
    final now = DateTime.now();
    final dueEntries = await store.due(now);
    StemMetrics.instance.setGauge(
      'stem.scheduler.due.entries',
      dueEntries.length.toDouble(),
    );
    var overdueCount = 0;
    Duration? maxOverdue;
    for (final entry in dueEntries) {
      final scheduled = entry.nextRunAt;
      if (scheduled != null && now.isAfter(scheduled)) {
        final overdue = now.difference(scheduled);
        overdueCount += 1;
        maxOverdue = maxOverdue == null
            ? overdue
            : (overdue > maxOverdue ? overdue : maxOverdue);
        StemMetrics.instance.recordDuration(
          'stem.scheduler.overdue.lag',
          overdue,
        );
      }
    }
    StemMetrics.instance.setGauge(
      'stem.scheduler.overdue.entries',
      overdueCount.toDouble(),
    );
    if (overdueCount > 0) {
      stemLogger.warning(
        'Scheduler lag detected for {count} schedule(s)',
        Context({
          'count': overdueCount.toString(),
          if (maxOverdue != null)
            'maxOverdueMs': maxOverdue.inMilliseconds.toString(),
        }),
      );
    }
    for (final entry in dueEntries) {
      await _signals.scheduleEntryDue(entry, now);
      await _dispatch(entry, now);
    }
  }

  Future<void> _dispatch(ScheduleEntry entry, DateTime now) async {
    if (!entry.enabled) return;

    Lock? lock;
    Timer? renewalTimer;
    Duration? jitterDelay;
    if (lockStore != null) {
      lock = await lockStore!.acquire(
        'stem:schedule:${entry.id}',
        ttl: lockTtl,
      );
      if (lock == null) {
        StemMetrics.instance.increment(
          'stem.scheduler.lock.contended',
          tags: {'schedule': entry.id},
        );
        return;
      }
      StemMetrics.instance.increment(
        'stem.scheduler.lock.acquired',
        tags: {'schedule': entry.id},
      );
      final renewMs = (lockTtl.inMilliseconds ~/ 2).clamp(
        100,
        lockTtl.inMilliseconds,
      );
      renewalTimer = Timer.periodic(Duration(milliseconds: renewMs), (_) async {
        final renewed = await lock!.renew(lockTtl);
        if (!renewed) {
          StemMetrics.instance.increment(
            'stem.scheduler.lock.renew_failed',
            tags: {'schedule': entry.id},
          );
        }
      });
    }

    final baseScheduled = entry.nextRunAt ?? now;
    final jitter = entry.jitter;
    jitterDelay = (jitter != null && jitter > Duration.zero)
        ? Duration(milliseconds: _random.nextInt(jitter.inMilliseconds + 1))
        : Duration.zero;
    final scheduledFor = baseScheduled.add(jitterDelay);
    final startedAt = DateTime.now();

    StemMetrics.instance.increment(
      'stem.scheduler.dispatch.attempts',
      tags: {'schedule': entry.id},
    );
    try {
      if (jitterDelay > Duration.zero) {
        await Future<void>.delayed(jitterDelay);
      }

      var envelope = Envelope(
        name: entry.taskName,
        args: entry.args,
        queue: entry.queue,
        headers: {'scheduled-from': 'beat', 'schedule-id': entry.id},
        meta: entry.kwargs.isEmpty
            ? entry.meta
            : {...entry.meta, 'kwargs': entry.kwargs},
      );
      if (signer != null) {
        envelope = await signer!.sign(envelope);
      }
      await broker.publish(envelope);

      final executedAt = DateTime.now();
      final duration = executedAt.difference(startedAt);
      StemMetrics.instance.recordDuration(
        'stem.scheduler.dispatch.duration',
        duration,
        tags: {'schedule': entry.id},
      );
      await store.markExecuted(
        entry.id,
        scheduledFor: scheduledFor,
        executedAt: executedAt,
        jitter: jitterDelay == Duration.zero ? null : jitterDelay,
        runDuration: duration,
        drift: executedAt.difference(scheduledFor),
      );
      final drift = executedAt.difference(scheduledFor);
      StemMetrics.instance.increment(
        'stem.scheduler.dispatch.success',
        tags: {'schedule': entry.id},
      );
      StemMetrics.instance.recordDuration(
        'stem.scheduler.drift',
        Duration(milliseconds: drift.inMilliseconds.abs()),
        tags: {'schedule': entry.id},
      );
      if (drift.inMilliseconds.abs() > 0) {
        stemLogger.info(
          'Schedule {schedule} drift recorded',
          Context({
            'schedule': entry.id,
            'driftMs': drift.inMilliseconds.toString(),
          }),
        );
      }
      await _signals.scheduleEntryDispatched(
        entry,
        scheduledFor: scheduledFor,
        executedAt: executedAt,
        drift: drift,
      );
    } on Object catch (error, stack) {
      stemLogger.warning(
        'Beat dispatch failed for {schedule}: {error}',
        Context({
          'schedule': entry.id,
          'error': error.toString(),
          'stack': stack.toString(),
        }),
      );
      try {
        final executedAt = DateTime.now();
        await store.markExecuted(
          entry.id,
          scheduledFor: scheduledFor,
          executedAt: executedAt,
          jitter: jitterDelay == Duration.zero ? null : jitterDelay,
          lastError: error.toString(),
          success: false,
          drift: executedAt.difference(scheduledFor),
        );
        StemMetrics.instance.increment(
          'stem.scheduler.dispatch.failed',
          tags: {'schedule': entry.id},
        );
      } on Exception catch (storeError, storeStack) {
        stemLogger.warning(
          'Failed to update schedule metadata for {schedule}',
          Context({
            'schedule': entry.id,
            'error': storeError.toString(),
            'stack': storeStack.toString(),
          }),
        );
      }
      await _signals.scheduleEntryFailed(
        entry,
        scheduledFor: scheduledFor,
        error: error,
        stackTrace: stack,
      );
    } finally {
      renewalTimer?.cancel();
      await lock?.release();
    }
  }
}
