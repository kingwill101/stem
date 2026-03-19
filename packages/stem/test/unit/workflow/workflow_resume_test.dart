import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/workflow_resume.dart';
import 'package:stem/src/workflow/core/workflow_script_context.dart';
import 'package:test/test.dart';

void main() {
  test('FlowContext.takeResumeValue decodes codec-backed DTO payloads', () {
    final context = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
      resumeData: const {'message': 'approved'},
    );

    final value = context.takeResumeValue<_ResumePayload>(
      codec: _resumePayloadCodec,
    );

    expect(value, isNotNull);
    expect(value!.message, 'approved');
    expect(
      context.takeResumeValue<_ResumePayload>(codec: _resumePayloadCodec),
      isNull,
    );
  });

  test('WorkflowScriptStepContext.takeResumeValue casts plain payloads', () {
    final context = _FakeWorkflowScriptStepContext(
      resumeData: const {'approvedBy': 'gateway'},
    );

    final value = context.takeResumeValue<Map<String, Object?>>();

    expect(value, isNotNull);
    expect(value!['approvedBy'], 'gateway');
    expect(context.takeResumeValue<Map<String, Object?>>(), isNull);
  });
}

class _ResumePayload {
  const _ResumePayload({required this.message});

  factory _ResumePayload.fromJson(Map<String, Object?> json) {
    return _ResumePayload(message: json['message'] as String);
  }

  final String message;

  Map<String, Object?> toJson() => {'message': message};
}

const _resumePayloadCodec = PayloadCodec<_ResumePayload>(
  encode: _encodeResumePayload,
  decode: _decodeResumePayload,
);

Object? _encodeResumePayload(_ResumePayload value) => value.toJson();

_ResumePayload _decodeResumePayload(Object? payload) {
  return _ResumePayload.fromJson(
    Map<String, Object?>.from(payload! as Map<Object?, Object?>),
  );
}

class _FakeWorkflowScriptStepContext implements WorkflowScriptStepContext {
  _FakeWorkflowScriptStepContext({Object? resumeData})
    : _resumeData = resumeData;

  Object? _resumeData;

  @override
  TaskEnqueuer? get enqueuer => null;

  @override
  int get iteration => 0;

  @override
  Map<String, Object?> get params => const {};

  @override
  Object? get previousResult => null;

  @override
  String get runId => 'run-1';

  @override
  String get stepName => 'step';

  @override
  int get stepIndex => 0;

  @override
  String get workflow => 'demo.workflow';

  @override
  Future<void> awaitEvent(
    String topic, {
    DateTime? deadline,
    Map<String, Object?>? data,
  }) async {}

  @override
  String idempotencyKey([String? scope]) =>
      'demo.workflow/run-1/${scope ?? stepName}';

  @override
  Future<void> sleep(Duration duration, {Map<String, Object?>? data}) async {}

  @override
  Object? takeResumeData() {
    final value = _resumeData;
    _resumeData = null;
    return value;
  }
}
