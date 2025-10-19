import 'package:test/test.dart';
import 'package:untitled6/src/observability/metrics.dart';

void main() {
  test('metrics counter aggregates by name and tags', () {
    final metrics = StemMetrics.instance;

    metrics.increment('tasks.succeeded', tags: {'task': 'foo'});
    metrics.increment('tasks.succeeded', tags: {'task': 'foo'});
    metrics.increment('tasks.failed', tags: {'task': 'foo'});

    final snapshot = metrics.snapshot();
    final counters = snapshot['counters'] as List<dynamic>;
    final succeeded = counters.firstWhere(
      (c) => c['name'] == 'tasks.succeeded',
    );
    expect(succeeded['value'], equals(2));
  });
}
