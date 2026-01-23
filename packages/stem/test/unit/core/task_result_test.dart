import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/task_result.dart';
import 'package:test/test.dart';

void main() {
  test('TaskResult status helpers reflect state', () {
    final succeeded = TaskResult(
      taskId: 'task-1',
      status: TaskStatus(
        id: 'task-1',
        state: TaskState.succeeded,
        attempt: 0,
      ),
    );
    final failed = TaskResult(
      taskId: 'task-2',
      status: TaskStatus(
        id: 'task-2',
        state: TaskState.failed,
        attempt: 0,
      ),
    );
    final cancelled = TaskResult(
      taskId: 'task-3',
      status: TaskStatus(
        id: 'task-3',
        state: TaskState.cancelled,
        attempt: 0,
      ),
    );

    expect(succeeded.isSucceeded, isTrue);
    expect(succeeded.isFailed, isFalse);

    expect(failed.isFailed, isTrue);
    expect(failed.isCancelled, isFalse);

    expect(cancelled.isCancelled, isTrue);
  });
}
