import 'package:stem/src/workflow/core/run_state.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:test/test.dart';

void main() {
  test('WorkflowResult status helpers', () {
    final state = RunState(
      id: 'run-1',
      workflow: 'demo',
      status: WorkflowStatus.completed,
      cursor: 0,
      params: const {},
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    );
    final result = WorkflowResult<int>(
      runId: 'run-1',
      status: WorkflowStatus.completed,
      state: state,
      value: 42,
      rawResult: 42,
    );

    expect(result.isCompleted, isTrue);
    expect(result.isFailed, isFalse);
  });

  test('WorkflowResult exposes typed value helpers', () {
    final state = RunState(
      id: 'run-1',
      workflow: 'demo',
      status: WorkflowStatus.completed,
      cursor: 0,
      params: const {},
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    );
    final result = WorkflowResult<int>(
      runId: 'run-1',
      status: WorkflowStatus.completed,
      state: state,
      value: 42,
      rawResult: 42,
    );

    expect(result.valueOr(7), 42);
    expect(result.requiredValue(), 42);
  });

  test('WorkflowResult.requiredValue throws when value is absent', () {
    final state = RunState(
      id: 'run-1',
      workflow: 'demo',
      status: WorkflowStatus.failed,
      cursor: 0,
      params: const {},
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    );
    final result = WorkflowResult<int>(
      runId: 'run-1',
      status: WorkflowStatus.failed,
      state: state,
    );

    expect(
      result.requiredValue,
      throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('run-1'),
          ),
        ),
      );
    expect(result.valueOr(7), 7);
  });
}
