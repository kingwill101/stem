import 'dart:math' as math;

import 'contracts.dart';

/// Exponential backoff with jitter, capped at a configurable duration.
class ExponentialJitterRetryStrategy implements RetryStrategy {
  ExponentialJitterRetryStrategy({
    this.base = const Duration(seconds: 2),
    this.max = const Duration(minutes: 5),
    int? seed,
  }) : _random = math.Random(seed);

  final Duration base;
  final Duration max;
  final math.Random _random;

  @override
  Duration nextDelay(int attempt, Object error, StackTrace stackTrace) {
    final raw = (base.inMilliseconds * math.pow(2, attempt).toDouble()).toInt();
    final capped = math.min(raw, max.inMilliseconds);
    final jitter = _random.nextInt(capped ~/ 4 + 1);
    final delayMs = (capped - jitter).clamp(0, max.inMilliseconds);
    return Duration(milliseconds: delayMs);
  }
}
