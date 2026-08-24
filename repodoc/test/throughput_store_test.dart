import 'package:repodoc/src/benchmarks/throughput_store.dart';
import 'package:test/test.dart';

void main() {
  test('parses supported benchmark stores and aliases', () {
    expect(ThroughputStore.parse('memory'), ThroughputStore.memory);
    expect(ThroughputStore.parse('sqlite'), ThroughputStore.sqlite);
    expect(ThroughputStore.parse('postgres'), ThroughputStore.postgres);
    expect(ThroughputStore.parse('postgresql'), ThroughputStore.postgres);
    expect(ThroughputStore.parse('redis'), ThroughputStore.redis);
    expect(ThroughputStore.parse('  Redis '), ThroughputStore.redis);
    expect(ThroughputStore.parse('PoStGrEs'), ThroughputStore.postgres);
  });

  test('rejects unknown benchmark stores', () {
    expect(() => ThroughputStore.parse('mysql'), throwsArgumentError);
  });
}
