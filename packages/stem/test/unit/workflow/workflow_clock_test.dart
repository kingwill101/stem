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

  test('SystemWorkflowClock returns current time', () {
    const clock = SystemWorkflowClock();
    final now = DateTime.now();
    final clockNow = clock.now();

    expect(clockNow.isAfter(now.subtract(const Duration(seconds: 1))), isTrue);
  });
}
