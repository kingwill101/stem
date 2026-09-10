// Copyright (c) 2025 Glenford Williams <hey@glenfordwilliams.com>
// SPDX-License-Identifier: MIT

/// Timer-driven compatibility facade for one-shot scheduling.
library;

import 'dart:async';
import 'dart:math';

import 'package:contextual/contextual.dart';
import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/observability/logging.dart';
import 'package:stem/src/scheduler/schedule_runner.dart';
import 'package:stem/src/security/signing.dart';

/// Periodically dispatches due schedules using [ScheduleRunner].
class Beat extends ScheduleRunner {
  /// Creates a scheduler backed by a queue broker.
  Beat({
    required ScheduleStore store,
    required QueueBroker broker,
    LockStore? lockStore,
    Duration tickInterval = const Duration(seconds: 1),
    Duration lockTtl = const Duration(seconds: 5),
    PayloadSigner? signer,
    Random? random,
  }) : this.withPublisher(
         store: store,
         publisher: broker,
         lockStore: lockStore,
         tickInterval: tickInterval,
         lockTtl: lockTtl,
         signer: signer,
         random: random,
       );

  /// Creates a scheduler using only publishing capability.
  Beat.withPublisher({
    required super.store,
    required super.publisher,
    super.lockStore,
    this.tickInterval = const Duration(seconds: 1),
    super.lockTtl,
    super.signer,
    super.random,
  });

  /// Interval between scheduling passes.
  final Duration tickInterval;

  /// Full broker, when this instance was created with one.
  QueueBroker get broker {
    final transport = publisher;
    if (transport is QueueBroker) return transport;
    throw StateError(
      'This Beat instance was created with a publish-only transport.',
    );
  }

  Timer? _timer;
  bool _running = false;

  /// Starts the periodic scheduling loop.
  Future<void> start() async {
    _timer ??= Timer.periodic(tickInterval, (_) => unawaited(_runPeriodic()));
  }

  Future<void> _runPeriodic() async {
    if (_running) return;
    _running = true;
    try {
      await runOnce();
    } on Object catch (error, stack) {
      stemLogger.warning(
        'Periodic scheduling pass failed',
        Context({'error': error.toString(), 'stack': stack.toString()}),
      );
    } finally {
      _running = false;
    }
  }

  /// Stops future ticks. Already running passes finish independently.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }
}
