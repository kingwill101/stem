import 'package:repodoc/src/benchmarks/throughput_statistics.dart';
import 'package:test/test.dart';

void main() {
  group('ThroughputStatistics', () {
    test('summarizes repeated values', () {
      final summary = ThroughputStatistics.summarize([10, 20, 30, 40, 50]);

      expect(summary['sample_count'], 5);
      expect(summary['median'], 30.0);
      expect(summary['p5'], 10.0);
      expect(summary['p95'], 50.0);
      expect(summary['minimum'], 10.0);
      expect(summary['maximum'], 50.0);
      expect(summary['mean'], 30.0);
      expect(summary['mad'], 10.0);
      expect(summary['cv'], closeTo(0.4714045, 0.000001));
    });

    test('averages the two middle values for an even sample count', () {
      final summary = ThroughputStatistics.summarize([10, 20, 30, 40]);

      expect(summary['median'], 25.0);
      expect(summary['mad'], 10.0);
    });

    test('returns null measurements for an empty sample', () {
      final summary = ThroughputStatistics.summarize(const <num>[]);

      expect(summary['sample_count'], 0);
      expect(summary['median'], isNull);
      expect(summary['p95'], isNull);
      expect(summary['p5'], isNull);
      expect(summary['mad'], isNull);
    });
  });
}
