import 'dart:async';
import 'dart:math';

import 'package:contextual/contextual.dart';

import '../core/contracts.dart';
import '../core/envelope.dart';
import '../observability/logging.dart';
import '../observability/metrics.dart';
import '../security/signing.dart';

class Beat {
  Beat({
    required this.store,
    required this.broker,
    this.lockStore,
    this.tickInterval = const Duration(seconds: 1),
    this.lockTtl = const Duration(seconds: 5),
    this.signer,
    Random? random,
  }) : _random = random ?? Random();

  final ScheduleStore store;
  final Broker broker;
  final LockStore? lockStore;
  final Duration tickInterval;
  final Duration lockTtl;
  final PayloadSigner? signer;

  final Random _random;

  Timer? _timer;
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> runOnce() => _tick();

  Future<void> _tick() async {
    if (!_running && _timer != null) return;
    final now = DateTime.now();
    final dueEntries = await store.due(now);
    for (final entry in dueEntries) {
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

    try {
      if (jitterDelay > Duration.zero) {
        await Future<void>.delayed(jitterDelay);
      }

      Envelope envelope = Envelope(
        name: entry.taskName,
        args: entry.args,
        queue: entry.queue,
        headers: {
          'scheduled-from': 'beat',
          'schedule-id': entry.id,
        },
        meta: entry.kwargs.isEmpty
            ? entry.meta
            : {
                ...entry.meta,
                'kwargs': entry.kwargs,
              },
      );
      if (signer != null) {
        envelope = await signer!.sign(envelope);
      }
      await broker.publish(envelope);

      final executedAt = DateTime.now();
      final duration = executedAt.difference(startedAt);
      await store.markExecuted(
        entry.id,
        scheduledFor: scheduledFor,
        executedAt: executedAt,
        jitter: jitterDelay == Duration.zero ? null : jitterDelay,
        lastError: null,
        success: true,
        runDuration: duration,
        drift: executedAt.difference(scheduledFor),
      );
    } catch (error, stack) {
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
      } catch (storeError, storeStack) {
        stemLogger.warning(
          'Failed to update schedule metadata for {schedule}',
          Context({
            'schedule': entry.id,
            'error': storeError.toString(),
            'stack': storeStack.toString(),
          }),
        );
      }
    } finally {
      renewalTimer?.cancel();
      await lock?.release();
    }
  }
}
