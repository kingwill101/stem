import 'package:stem/stem.dart';
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

  test('WorkflowResult exposes raw payload decode helpers', () {
    final state = RunState(
      id: 'run-1',
      workflow: 'demo',
      status: WorkflowStatus.completed,
      cursor: 0,
      params: const {},
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    );
    final codec = PayloadCodec<Map<String, Object?>>.map(
      encode: (value) => value,
      decode: (json) => json,
      typeName: 'ReceiptMap',
    );
    final result = WorkflowResult<Object?>(
      runId: 'run-1',
      status: WorkflowStatus.completed,
      state: state,
      rawResult: const {'id': 'receipt-1'},
    );

    expect(
      result.payloadAs<Map<String, Object?>>(codec: codec),
      equals(const {'id': 'receipt-1'}),
    );
    expect(
      result.payloadJson<_WorkflowReceipt>(
        decode: _WorkflowReceipt.fromJson,
      ),
      isA<_WorkflowReceipt>()
          .having((value) => value.id, 'id', 'receipt-1'),
    );
    expect(
      result.payloadVersionedJson<_WorkflowReceipt>(
        version: 2,
        decode: _WorkflowReceipt.fromVersionedJson,
      ),
      isA<_WorkflowReceipt>()
          .having((value) => value.id, 'id', 'receipt-1'),
    );
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

class _WorkflowReceipt {
  const _WorkflowReceipt({required this.id});

  factory _WorkflowReceipt.fromJson(Map<String, dynamic> json) {
    return _WorkflowReceipt(id: json['id'] as String);
  }

  factory _WorkflowReceipt.fromVersionedJson(
    Map<String, dynamic> json,
    int version,
  ) {
    expect(version, 2);
    return _WorkflowReceipt(id: json['id'] as String);
  }

  final String id;
}
