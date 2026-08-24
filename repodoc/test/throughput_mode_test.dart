import 'package:repodoc/src/benchmarks/throughput.dart';
import 'package:repodoc/src/benchmarks/throughput_mode.dart';
import 'package:test/test.dart';

void main() {
  group('ThroughputMode', () {
    test('parses canonical names and aliases', () {
      expect(ThroughputMode.parse('steady-state'), ThroughputMode.steadyState);
      expect(ThroughputMode.parse('enqueue'), ThroughputMode.enqueueOnly);
      expect(
        ThroughputMode.parse('worker-drain'),
        ThroughputMode.prefilledDrain,
      );
    });

    test('rejects unknown modes', () {
      expect(() => ThroughputMode.parse('burst'), throwsArgumentError);
    });
  });

  group('parseThroughputDuration', () {
    test('parses supported units', () {
      expect(
        parseThroughputDuration('250ms'),
        const Duration(milliseconds: 250),
      );
      expect(parseThroughputDuration('5s'), const Duration(seconds: 5));
      expect(parseThroughputDuration('2m'), const Duration(minutes: 2));
      expect(parseThroughputDuration('1h'), const Duration(hours: 1));
    });

    test('rejects invalid or zero durations', () {
      expect(() => parseThroughputDuration('5'), throwsArgumentError);
      expect(() => parseThroughputDuration('0s'), throwsArgumentError);
    });
  });
}
