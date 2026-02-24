import 'package:stem/stem.dart';
import 'package:stem/testing.dart';
import 'package:stem/src/workflow/core/workflow_clock.dart';
import 'package:test/test.dart';

void main() {
  test('FakeWorkflowClock advances time', () {
    final initial = DateTime.parse('2025-01-01T00:00:00Z');
    final clock = FakeWorkflowClock(initial);

    expect(clock.now(), initial);
    clock.advance(const Duration(seconds: 5));
    expect(clock.now(), DateTime.parse('2025-01-01T00:00:05Z'));
  });

  test('SystemWorkflowClock respects scoped Stem clock overrides', () {
    const clock = SystemWorkflowClock();
    final fake = FakeStemClock(DateTime.parse('2025-01-01T00:00:10Z'));

    final clockNow = withStemClock(fake, clock.now);

    expect(clockNow, DateTime.parse('2025-01-01T00:00:10Z'));
  });
}
