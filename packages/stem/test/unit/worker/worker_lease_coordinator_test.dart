import 'dart:async';

import 'package:stem/memory.dart';
import 'package:stem/src/worker/worker_lease_coordinator.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('renews a short lease before the default minimum interval', () async {
    final broker = _RecordingLeaseBroker();
    final coordinator = WorkerLeaseCoordinator(
      broker: broker,
      onLeaseUpdated: (_) {},
      onLeaseRenewed: (_) {},
      onRenewalFailure: (_, error, _) {
        throw StateError('Unexpected lease renewal failure: $error');
      },
    );
    final delivery = Delivery(
      envelope: Envelope(name: 'short-lease.test', args: const {}),
      receipt: 'short-lease-receipt',
      leaseExpiresAt: DateTime.now().add(const Duration(milliseconds: 300)),
    );

    coordinator.schedule(delivery);
    try {
      await _waitFor(
        () => broker.attempts >= 1,
        timeout: const Duration(milliseconds: 600),
      );
      expect(broker.attempts, greaterThanOrEqualTo(1));
    } finally {
      coordinator.cancelAll();
      broker.dispose();
    }
  });

  test('passes the full lease duration instead of the timer cadence', () async {
    final broker = _RecordingLeaseBroker();
    final coordinator = WorkerLeaseCoordinator(
      broker: broker,
      minimumInterval: const Duration(milliseconds: 5),
      maximumInterval: const Duration(seconds: 1),
      onLeaseUpdated: (_) {},
      onLeaseRenewed: (_) {},
      onRenewalFailure: (_, error, _) {
        throw StateError('Unexpected lease renewal failure: $error');
      },
    );
    final delivery = Delivery(
      envelope: Envelope(
        name: 'full-lease.test',
        args: const {},
        visibilityTimeout: const Duration(milliseconds: 200),
      ),
      receipt: 'full-lease-receipt',
      leaseExpiresAt: DateTime.now().add(const Duration(milliseconds: 200)),
    );

    coordinator.schedule(delivery);
    try {
      await _waitFor(() => broker.attempts >= 1);
      expect(broker.durations.first, const Duration(milliseconds: 200));
    } finally {
      coordinator.cancelAll();
      broker.dispose();
    }
  });

  test(
    'restarts a short manually extended lease before the default minimum',
    () async {
      final broker = _RecordingLeaseBroker();
      final coordinator = WorkerLeaseCoordinator(
        broker: broker,
        onLeaseUpdated: (_) {},
        onLeaseRenewed: (_) {},
        onRenewalFailure: (_, error, _) {
          throw StateError('Unexpected lease renewal failure: $error');
        },
      );
      final delivery = Delivery(
        envelope: Envelope(name: 'short-lease-restart.test', args: const {}),
        receipt: 'short-lease-restart-receipt',
        leaseExpiresAt: DateTime.now().add(const Duration(seconds: 10)),
      );

      coordinator.restart(delivery, const Duration(milliseconds: 300));
      try {
        await _waitFor(
          () => broker.attempts >= 1,
          timeout: const Duration(milliseconds: 600),
        );
        expect(broker.attempts, greaterThanOrEqualTo(1));
      } finally {
        coordinator.cancelAll();
        broker.dispose();
      }
    },
  );

  test('keeps same-receipt redeliveries on independent timers', () async {
    final broker = _RecordingLeaseBroker();
    final coordinator = WorkerLeaseCoordinator(
      broker: broker,
      minimumInterval: const Duration(milliseconds: 5),
      maximumInterval: const Duration(milliseconds: 20),
      onLeaseUpdated: (_) {},
      onLeaseRenewed: (_) {},
      onRenewalFailure: (_, error, _) {
        throw StateError('Unexpected lease renewal failure: $error');
      },
    );
    final first = Delivery(
      envelope: Envelope(name: 'same-receipt.test', args: const {}),
      receipt: 'reused-receipt',
      leaseExpiresAt: DateTime.now().add(const Duration(milliseconds: 40)),
    );
    final redelivery = Delivery(
      envelope: first.envelope,
      receipt: first.receipt,
      leaseExpiresAt: DateTime.now().add(const Duration(milliseconds: 40)),
    );

    coordinator
      ..schedule(first)
      ..schedule(redelivery);
    try {
      await _waitFor(
        () => broker.attempts >= 2,
        timeout: const Duration(milliseconds: 600),
      );
      expect(broker.attempts, greaterThanOrEqualTo(2));
    } finally {
      coordinator
        ..cancel(first)
        ..cancel(redelivery)
        ..cancelAll();
      broker.dispose();
    }
  });

  test('contains renewal failures and recovers on a later attempt', () async {
    final broker = _FlakyLeaseBroker();
    final updated = <Delivery>[];
    final renewed = <Delivery>[];
    final failures = <Object>[];
    final coordinator = WorkerLeaseCoordinator(
      broker: broker,
      minimumInterval: const Duration(milliseconds: 5),
      maximumInterval: const Duration(milliseconds: 20),
      onLeaseUpdated: updated.add,
      onLeaseRenewed: renewed.add,
      onRenewalFailure: (_, error, _) => failures.add(error),
    );
    final delivery = Delivery(
      envelope: Envelope(name: 'lease.test', args: const {}),
      receipt: 'lease-receipt',
      leaseExpiresAt: DateTime.now().add(const Duration(milliseconds: 30)),
    );

    coordinator.schedule(delivery);
    try {
      await _waitFor(() => broker.attempts >= 2);
      expect(failures, hasLength(1));
      expect(updated, isNotEmpty);
      expect(renewed, isNotEmpty);
    } finally {
      coordinator.cancelAll();
      broker.dispose();
    }
  });

  test(
    'retries a failed renewal before the original interval elapses',
    () async {
      final broker = _TimedFlakyLeaseBroker();
      final coordinator = WorkerLeaseCoordinator(
        broker: broker,
        minimumInterval: const Duration(milliseconds: 5),
        maximumInterval: const Duration(seconds: 1),
        onLeaseUpdated: (_) {},
        onLeaseRenewed: (_) {},
        onRenewalFailure: (_, error, _) => broker.failures.add(error),
      );
      final delivery = Delivery(
        envelope: Envelope(name: 'lease-retry.test', args: const {}),
        receipt: 'lease-retry-receipt',
        leaseExpiresAt: DateTime.now().add(const Duration(milliseconds: 100)),
      );

      coordinator.schedule(delivery);
      try {
        await _waitFor(() => broker.attempts >= 2);
        expect(broker.failures, hasLength(1));
        expect(
          broker.attemptTimes[1].difference(broker.attemptTimes[0]),
          lessThan(const Duration(milliseconds: 50)),
        );
      } finally {
        coordinator.cancelAll();
        broker.dispose();
      }
    },
  );

  test('does not restart after an in-flight renewal is cancelled', () async {
    final broker = _BlockingLeaseBroker();
    final failures = <Object>[];
    final coordinator = WorkerLeaseCoordinator(
      broker: broker,
      minimumInterval: const Duration(milliseconds: 5),
      maximumInterval: const Duration(milliseconds: 20),
      onLeaseUpdated: (_) {},
      onLeaseRenewed: (_) {},
      onRenewalFailure: (_, error, _) => failures.add(error),
    );
    final delivery = Delivery(
      envelope: Envelope(name: 'lease-cancel.test', args: const {}),
      receipt: 'lease-cancel-receipt',
      leaseExpiresAt: DateTime.now().add(const Duration(milliseconds: 30)),
    );

    coordinator.schedule(delivery);
    try {
      await broker.started.future.timeout(const Duration(seconds: 1));
      coordinator.cancel(delivery);
      broker.release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(broker.attempts, 1);
      expect(failures, isEmpty);
    } finally {
      coordinator.cancelAll();
      broker.dispose();
    }
  });
}

class _FlakyLeaseBroker extends InMemoryBroker {
  _FlakyLeaseBroker()
    : super(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );

  int attempts = 0;

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    attempts += 1;
    if (attempts == 1) {
      throw StateError('simulated lease renewal failure');
    }
  }
}

class _RecordingLeaseBroker extends InMemoryBroker {
  _RecordingLeaseBroker()
    : super(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );

  int attempts = 0;
  final durations = <Duration>[];

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    attempts += 1;
    durations.add(by);
  }
}

class _TimedFlakyLeaseBroker extends InMemoryBroker {
  _TimedFlakyLeaseBroker()
    : super(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );

  final attemptTimes = <DateTime>[];
  final failures = <Object>[];

  int get attempts => attemptTimes.length;

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    attemptTimes.add(DateTime.now());
    if (attemptTimes.length == 1) {
      throw StateError('simulated lease renewal failure');
    }
  }
}

class _BlockingLeaseBroker extends InMemoryBroker {
  _BlockingLeaseBroker()
    : super(
        delayedInterval: const Duration(milliseconds: 5),
        claimInterval: const Duration(milliseconds: 20),
      );

  final started = Completer<void>();
  final release = Completer<void>();
  int attempts = 0;

  @override
  Future<void> extendLease(Delivery delivery, Duration by) async {
    attempts += 1;
    if (!started.isCompleted) started.complete();
    await release.future;
    throw StateError('simulated late lease renewal failure');
  }
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
