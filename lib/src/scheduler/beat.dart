import 'dart:async';
import 'dart:math';

import '../core/contracts.dart';
import '../core/envelope.dart';

class Beat {
  Beat({
    required this.store,
    required this.broker,
    this.lockStore,
    this.tickInterval = const Duration(seconds: 1),
    this.lockTtl = const Duration(seconds: 5),
    Random? random,
  }) : _random = random ?? Random();

  final ScheduleStore store;
  final Broker broker;
  final LockStore? lockStore;
  final Duration tickInterval;
  final Duration lockTtl;

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
    if (lockStore != null) {
      lock = await lockStore!.acquire(
        'stem:schedule:${entry.id}',
        ttl: lockTtl,
      );
      if (lock == null) {
        return;
      }
    }

    try {
      final jitter = entry.jitter;
      final jitterDelay = (jitter != null && jitter > Duration.zero)
          ? Duration(milliseconds: _random.nextInt(jitter.inMilliseconds + 1))
          : Duration.zero;
      if (jitterDelay > Duration.zero) {
        await Future<void>.delayed(jitterDelay);
      }

      final envelope = Envelope(
        name: entry.taskName,
        args: entry.args,
        queue: entry.queue,
        headers: {'scheduled-from': 'beat', 'schedule-id': entry.id},
      );
      await broker.publish(envelope, queue: entry.queue);

      final updated = entry.copyWith(lastRunAt: DateTime.now());
      await store.upsert(updated);
    } finally {
      await lock?.release();
    }
  }
}
