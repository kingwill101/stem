import 'package:test/test.dart';
import 'package:stem/src/observability/metrics.dart';

void main() {
  test('metrics counter aggregates by name and tags', () {
    final metrics = StemMetrics.instance;

    metrics.reset();
    metrics.increment('stem.tasks.succeeded', tags: {'task': 'foo'});
    metrics.increment('stem.tasks.succeeded', tags: {'task': 'foo'});
    metrics.increment('stem.tasks.failed', tags: {'task': 'foo'});

    final snapshot = metrics.snapshot();
    final counters = snapshot['counters'] as List<dynamic>;
    final succeeded = counters.firstWhere(
      (c) => c['name'] == 'stem.tasks.succeeded',
    );
    expect(succeeded['value'], equals(2));
  });
}
