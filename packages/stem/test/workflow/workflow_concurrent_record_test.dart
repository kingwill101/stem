import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('logical IDs are stable and unambiguous across scopes', () {
    StepInvocationId id(List<String> path, String name, int iteration) =>
        StepInvocationId.scoped(
          branchPath: path,
          stepName: name,
          iteration: iteration,
        );

    expect(id(['a', 'b'], 'work', 0), id(['a', 'b'], 'work', 0));
    expect(id(['a/b'], 'work', 0), isNot(id(['a', 'b'], 'work', 0)));
    expect(id(['a'], 'b/work', 0), isNot(id(['a/b'], 'work', 0)));
    expect(id([], 'work', 1), isNot(id([], 'work', 0)));
  });

  test('JSON round trip preserves completed null and detached payloads', () {
    final payload = <String, Object?>{
      'nested': <Object?>['original'],
    };
    final record = WorkflowConcurrentStepRecord(
      runId: 'run',
      invocationId: 'invocation',
      branch: '',
      stepName: 'step',
      stepIndex: 0,
      iteration: 0,
      revision: 1,
      status: WorkflowConcurrentStepStatus.completed,
      executionId: 'execution',
      updatedAt: DateTime.utc(2024),
      suspensionData: {'payload': payload},
    );
    (payload['nested']! as List<Object?>)[0] = 'changed';
    final restored = WorkflowConcurrentStepRecord.fromJson(
      (jsonDecode(jsonEncode(record.toJson())) as Map).cast<String, Object?>(),
    );
    expect(restored.status, WorkflowConcurrentStepStatus.completed);
    expect(restored.value, isNull);
    expect(restored.suspensionData, {
      'payload': {
        'nested': ['original'],
      },
    });
    expect(
      () => restored.suspensionData!['payload'] = 'changed',
      throwsUnsupportedError,
    );
    expect(restored.toJson(), record.toJson());
  });

  test('malformed durable records are rejected at the decoding boundary', () {
    expect(
      () => WorkflowConcurrentStepRecord.fromJson(const {}),
      throwsFormatException,
    );
    expect(
      () => StepInvocationId.scoped(
        branchPath: const [],
        stepName: '',
        iteration: 0,
      ),
      throwsArgumentError,
    );
  });
}
