import 'package:repodoc/src/benchmarks/throughput_scenario.dart';
import 'package:test/test.dart';

void main() {
  group('ThroughputScenario', () {
    test('parses canonical names and useful aliases', () {
      expect(ThroughputScenario.parse('success'), ThroughputScenario.success);
      expect(ThroughputScenario.parse('nack'), ThroughputScenario.retry);
      expect(
        ThroughputScenario.parse('deadletter'),
        ThroughputScenario.deadLetter,
      );
      expect(ThroughputScenario.parse('renewal'), ThroughputScenario.lease);
    });

    test('rejects unknown scenarios', () {
      expect(() => ThroughputScenario.parse('unknown'), throwsArgumentError);
    });
  });
}
