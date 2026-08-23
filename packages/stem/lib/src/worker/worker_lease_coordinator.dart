import 'dart:async';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/envelope.dart';

/// Coordinates visibility/lease renewal for active worker deliveries.
///
/// Lease renewal is deliberately isolated from task execution. A failed
/// renewal is reported to the worker and retried on a shorter interval rather
/// than waiting until the original lease deadline. The broker remains the
/// source of truth: if a lease is ultimately lost, normal at-least-once
/// delivery and terminal result deduplication handle the resulting redelivery.
class WorkerLeaseCoordinator {
  /// Creates a lease coordinator for [broker].
  WorkerLeaseCoordinator({
    required QueueBroker broker,
    required void Function(Delivery delivery) onLeaseUpdated,
    required void Function(Delivery delivery) onLeaseRenewed,
    required void Function(
      Delivery delivery,
      Object error,
      StackTrace stackTrace,
    )
    onRenewalFailure,
    DateTime Function()? now,
    this.minimumInterval = const Duration(seconds: 1),
    this.maximumInterval = const Duration(seconds: 30),
  }) : _broker = broker,
       _onLeaseUpdated = onLeaseUpdated,
       _onLeaseRenewed = onLeaseRenewed,
       _onRenewalFailure = onRenewalFailure,
       _now = now ?? DateTime.now {
    if (minimumInterval <= Duration.zero) {
      throw ArgumentError.value(
        minimumInterval,
        'minimumInterval',
        'must be positive',
      );
    }
    if (maximumInterval < minimumInterval) {
      throw ArgumentError.value(
        maximumInterval,
        'maximumInterval',
        'must be at least minimumInterval',
      );
    }
  }

  final QueueBroker _broker;
  final void Function(Delivery delivery) _onLeaseUpdated;
  final void Function(Delivery delivery) _onLeaseRenewed;
  final void Function(
    Delivery delivery,
    Object error,
    StackTrace stackTrace,
  )
  _onRenewalFailure;
  final DateTime Function() _now;

  /// Lower bound for renewal intervals when the lease permits it.
  ///
  /// A lease deadline takes precedence: short leases must be renewed before
  /// expiry even when that requires using an interval below this value.
  final Duration minimumInterval;

  /// Upper bound for renewal intervals.
  final Duration maximumInterval;

  final Map<Delivery, Timer> _timers = {};
  final Set<Delivery> _renewalsInFlight = {};
  final Map<Delivery, int> _generations = {};
  int _generationSeed = 0;

  /// Schedules renewal based on the delivery's current lease expiry.
  void schedule(Delivery delivery) {
    final expiresAt = delivery.leaseExpiresAt;
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(_now()).inMilliseconds;
    if (remaining <= 0) return;

    final halfRemaining = Duration(milliseconds: remaining ~/ 2);
    final interval = _clampInterval(halfRemaining);
    final leaseDuration = _leaseDuration(
      delivery,
      Duration(milliseconds: remaining),
    );
    _start(delivery, interval, leaseDuration);
    _onLeaseUpdated(delivery);
  }

  /// Restarts renewal after an explicit lease extension.
  void restart(Delivery delivery, Duration leaseDuration) {
    final halfDuration = Duration(
      milliseconds: leaseDuration.inMilliseconds ~/ 2,
    );
    final interval = _clampInterval(halfDuration);
    _start(delivery, interval, leaseDuration);
    _onLeaseUpdated(delivery);
  }

  /// Cancels renewal for one delivery.
  void cancel(Delivery delivery) {
    _timers.remove(delivery)?.cancel();
    _generations.remove(delivery);
  }

  /// Cancels all renewal timers.
  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _generations.clear();
  }

  Duration _clampInterval(Duration value) {
    // The value is derived from half of the remaining lease, so preserving it
    // is safer than applying the normal minimum to short-lived leases.
    if (value <= Duration.zero) return minimumInterval;
    if (value > maximumInterval) return maximumInterval;
    return value;
  }

  Duration _leaseDuration(Delivery delivery, Duration remaining) {
    final configured = delivery.envelope.visibilityTimeout;
    if (configured != null && configured > Duration.zero) {
      return configured;
    }
    return remaining;
  }

  void _start(
    Delivery delivery,
    Duration interval,
    Duration leaseDuration,
  ) {
    cancel(delivery);
    final generation = ++_generationSeed;
    _generations[delivery] = generation;
    final timer = Timer.periodic(interval, (_) {
      if (!_renewalsInFlight.add(delivery)) return;
      unawaited(_renew(delivery, interval, leaseDuration, generation));
    });
    _timers[delivery] = timer;
  }

  Future<void> _renew(
    Delivery delivery,
    Duration interval,
    Duration leaseDuration,
    int generation,
  ) async {
    try {
      await _broker.extendLease(delivery, leaseDuration);
      if (!_isCurrent(delivery, generation)) return;
      _onLeaseUpdated(delivery);
      _onLeaseRenewed(delivery);
    } on Object catch (error, stackTrace) {
      if (!_isCurrent(delivery, generation)) return;
      _onRenewalFailure(delivery, error, stackTrace);
      _start(delivery, _retryInterval(interval), leaseDuration);
    } finally {
      _renewalsInFlight.remove(delivery);
    }
  }

  bool _isCurrent(Delivery delivery, int generation) =>
      _generations[delivery] == generation;

  Duration _retryInterval(Duration interval) {
    final milliseconds = interval.inMilliseconds;
    if (milliseconds <= 1) return const Duration(milliseconds: 1);
    final retryMilliseconds = milliseconds ~/ 2;
    final minimumMilliseconds = minimumInterval.inMilliseconds;
    return Duration(
      milliseconds: retryMilliseconds < minimumMilliseconds
          ? retryMilliseconds
          : minimumMilliseconds,
    );
  }
}
