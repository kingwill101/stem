import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:test/test.dart';

void main() {
  test('WorkflowCancellationPolicy isEmpty reflects configured limits', () {
    const empty = WorkflowCancellationPolicy();
    expect(empty.isEmpty, isTrue);

    const withRun = WorkflowCancellationPolicy(
      maxRunDuration: Duration(minutes: 5),
    );
    expect(withRun.isEmpty, isFalse);
  });

  test('WorkflowCancellationPolicy serializes and parses durations', () {
    const policy = WorkflowCancellationPolicy(
      maxRunDuration: Duration(minutes: 10),
      maxSuspendDuration: Duration(seconds: 30),
    );

    final json = policy.toJson();
    expect(json['maxRunDuration'], const Duration(minutes: 10).inMilliseconds);
    expect(
      json['maxSuspendDuration'],
      const Duration(seconds: 30).inMilliseconds,
    );

    final parsed = WorkflowCancellationPolicy.fromJson(json)!;
    expect(parsed.maxRunDuration, const Duration(minutes: 10));
    expect(parsed.maxSuspendDuration, const Duration(seconds: 30));
  });

  test(
    'WorkflowCancellationPolicy parses numeric strings and invalid input',
    () {
      final parsed = WorkflowCancellationPolicy.fromJson({
        'maxRunDuration': '60000',
        'maxSuspendDuration': 2500.0,
      })!;

      expect(parsed.maxRunDuration, const Duration(milliseconds: 60000));
      expect(parsed.maxSuspendDuration, const Duration(milliseconds: 2500));

      expect(WorkflowCancellationPolicy.fromJson('invalid'), isNull);
    },
  );

  test('WorkflowCancellationPolicy copyWith preserves existing values', () {
    const original = WorkflowCancellationPolicy(
      maxRunDuration: Duration(minutes: 1),
    );

    final updated = original.copyWith(
      maxSuspendDuration: const Duration(seconds: 5),
    );

    expect(updated.maxRunDuration, const Duration(minutes: 1));
    expect(updated.maxSuspendDuration, const Duration(seconds: 5));
  });
}
