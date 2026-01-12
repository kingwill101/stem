import 'package:property_testing/property_testing.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

import 'property_test_helpers.dart';

class _IntervalCase {
  _IntervalCase(this.everyMs, this.offsetMs);

  final int everyMs;
  final int offsetMs;
}

void main() {
  test('interval schedules are monotonic after now', () async {
    final gen = Gen.integer(min: 1, max: 60 * 1000).flatMap((everyMs) {
      return Gen.integer(min: 0, max: everyMs * 5).map(
        (offsetMs) => _IntervalCase(everyMs, offsetMs),
      );
    });

    final runner = PropertyTestRunner<_IntervalCase>(
      gen,
      (sample) async {
        final spec = IntervalScheduleSpec(
          every: Duration(milliseconds: sample.everyMs),
        );
        final now = DateTime.utc(2025, 1, 1, 12, 0, 0);
        final lastRunAt = now.subtract(
          Duration(milliseconds: sample.offsetMs),
        );
        final entry = ScheduleEntry(
          id: 'schedule-${sample.everyMs}-${sample.offsetMs}',
          taskName: 'demo.task',
          queue: 'default',
          spec: spec,
          lastRunAt: lastRunAt,
        );

        final calculator = ScheduleCalculator();
        final nextRun = calculator.nextRun(
          entry,
          now,
          includeJitter: false,
        );

        expect(nextRun.isBefore(now), isFalse);
      },
      fastPropertyConfig,
    );

    await expectProperty(
      runner,
      description: 'interval monotonicity',
    );
  });
}
