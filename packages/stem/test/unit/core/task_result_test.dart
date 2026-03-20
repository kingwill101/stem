import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
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

  test('TaskResult exposes typed value helpers', () {
    final result = TaskResult<int>(
      taskId: 'task-1',
      status: TaskStatus(
        id: 'task-1',
        state: TaskState.succeeded,
        attempt: 0,
        payload: 42,
      ),
      value: 42,
      rawPayload: 42,
    );

    expect(result.valueOr(7), 42);
    expect(result.requiredValue(), 42);
  });

  test('TaskResult exposes raw payload decode helpers', () {
    final codec = PayloadCodec<Map<String, Object?>>.map(
      encode: (value) => value,
      decode: (json) => json,
      typeName: 'ReceiptMap',
    );
    final result = TaskResult<Object?>(
      taskId: 'task-1',
      status: TaskStatus(
        id: 'task-1',
        state: TaskState.succeeded,
        attempt: 0,
        payload: const {'id': 'receipt-1'},
      ),
      rawPayload: const {'id': 'receipt-1'},
    );

    expect(
      result.payloadAs<Map<String, Object?>>(codec: codec),
      equals(const {'id': 'receipt-1'}),
    );
    expect(
      result.payloadJson<_TaskReceipt>(
        decode: _TaskReceipt.fromJson,
      ),
      isA<_TaskReceipt>().having((value) => value.id, 'id', 'receipt-1'),
    );
  });

  test('TaskResult.requiredValue throws when value is absent', () {
    final result = TaskResult<int>(
      taskId: 'task-1',
      status: TaskStatus(
        id: 'task-1',
        state: TaskState.failed,
        attempt: 1,
      ),
    );

    expect(
      result.requiredValue,
      throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('task-1'),
          ),
        ),
      );
    expect(result.valueOr(7), 7);
  });
}

class _TaskReceipt {
  const _TaskReceipt({required this.id});

  factory _TaskReceipt.fromJson(Map<String, dynamic> json) {
    return _TaskReceipt(id: json['id'] as String);
  }

  final String id;
}
