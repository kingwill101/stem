import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
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

  test('FlowContext.sleepUntilResumed suspends once then resumes', () {
    final firstContext = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
    );

    final firstResult = firstContext.sleepUntilResumed(
      const Duration(seconds: 1),
      data: const {'phase': 'initial'},
    );

    expect(firstResult, isFalse);
    final control = firstContext.takeControl();
    expect(control, isNotNull);
    expect(control!.type, FlowControlType.sleep);

    final resumedContext = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
      resumeData: true,
    );

    final resumed = resumedContext.sleepUntilResumed(
      const Duration(seconds: 1),
    );

    expect(resumed, isTrue);
    expect(resumedContext.takeControl(), isNull);
  });

  test(
    'FlowContext.waitForEventValue registers watcher then decodes payload',
    () {
      final firstContext = FlowContext(
        workflow: 'demo',
        runId: 'run-1',
        stepName: 'wait',
        params: const {},
        previousResult: null,
        stepIndex: 0,
      );

      final firstResult = firstContext.waitForEventValue<_ResumePayload>(
        'demo.event',
        codec: _resumePayloadCodec,
      );

      expect(firstResult, isNull);
      final control = firstContext.takeControl();
      expect(control, isNotNull);
      expect(control!.type, FlowControlType.waitForEvent);
      expect(control.topic, 'demo.event');

      final resumedContext = FlowContext(
        workflow: 'demo',
        runId: 'run-1',
        stepName: 'wait',
        params: const {},
        previousResult: null,
        stepIndex: 0,
        resumeData: const {'message': 'approved'},
      );

      final resumed = resumedContext.waitForEventValue<_ResumePayload>(
        'demo.event',
        codec: _resumePayloadCodec,
      );

      expect(resumed, isNotNull);
      expect(resumed!.message, 'approved');
      expect(resumedContext.takeControl(), isNull);
    },
  );

  test('FlowContext.waitForEventRef reuses topic and codec', () {
    const event = WorkflowEventRef<_ResumePayload>(
      topic: 'demo.event',
      codec: _resumePayloadCodec,
    );
    final firstContext = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
    );

    final firstResult = firstContext.waitForEventRef(event);

    expect(firstResult, isNull);
    final control = firstContext.takeControl();
    expect(control, isNotNull);
    expect(control!.topic, 'demo.event');

    final resumedContext = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
      resumeData: const {'message': 'approved'},
    );

    final resumed = resumedContext.waitForEventRef(event);
    expect(resumed?.message, 'approved');
  });

  test(
    'WorkflowScriptStepContext helpers suspend once and decode resumed values',
    () {
      final sleeping = _FakeWorkflowScriptStepContext();

      final firstSleep = sleeping.sleepUntilResumed(
        const Duration(milliseconds: 10),
      );

      expect(firstSleep, isFalse);
      expect(sleeping.sleepCalls, hasLength(1));

      final resumedSleep = _FakeWorkflowScriptStepContext(resumeData: true);
      expect(
        resumedSleep.sleepUntilResumed(const Duration(milliseconds: 10)),
        isTrue,
      );
      expect(resumedSleep.sleepCalls, isEmpty);

      final waiting = _FakeWorkflowScriptStepContext();
      final firstEvent = waiting.waitForEventValue<_ResumePayload>(
        'demo.event',
        codec: _resumePayloadCodec,
      );
      expect(firstEvent, isNull);
      expect(waiting.awaitedTopics, ['demo.event']);

      final resumedEvent = _FakeWorkflowScriptStepContext(
        resumeData: const {'message': 'approved'},
      );
      final resumedValue = resumedEvent.waitForEventValue<_ResumePayload>(
        'demo.event',
        codec: _resumePayloadCodec,
      );
      expect(resumedValue, isNotNull);
      expect(resumedValue!.message, 'approved');
      expect(resumedEvent.awaitedTopics, isEmpty);
    },
  );

  test('WorkflowScriptStepContext.waitForEventRef reuses topic and codec', () {
    const event = WorkflowEventRef<_ResumePayload>(
      topic: 'demo.event',
      codec: _resumePayloadCodec,
    );
    final waiting = _FakeWorkflowScriptStepContext();
    final firstEvent = waiting.waitForEventRef(event);
    expect(firstEvent, isNull);
    expect(waiting.awaitedTopics, ['demo.event']);

    final resumed = _FakeWorkflowScriptStepContext(
      resumeData: const {'message': 'approved'},
    );
    final resumedValue = resumed.waitForEventRef(event);
    expect(resumedValue?.message, 'approved');
  });
}

class _ResumePayload {
  const _ResumePayload({required this.message});

  factory _ResumePayload.fromJson(Map<String, Object?> json) {
    return _ResumePayload(message: json['message']! as String);
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
  final map = payload! as Map<Object?, Object?>;
  return _ResumePayload.fromJson(
    Map<String, Object?>.from(map),
  );
}

class _FakeWorkflowScriptStepContext implements WorkflowScriptStepContext {
  _FakeWorkflowScriptStepContext({Object? resumeData})
    : _resumeData = resumeData;

  Object? _resumeData;
  final List<String> awaitedTopics = <String>[];
  final List<Duration> sleepCalls = <Duration>[];

  @override
  TaskEnqueuer? get enqueuer => null;

  @override
  Never? get workflows => null;

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
  }) async {
    awaitedTopics.add(topic);
  }

  @override
  String idempotencyKey([String? scope]) =>
      'demo.workflow/run-1/${scope ?? stepName}';

  @override
  Future<void> sleep(Duration duration, {Map<String, Object?>? data}) async {
    sleepCalls.add(duration);
  }

  @override
  Object? takeResumeData() {
    final value = _resumeData;
    _resumeData = null;
    return value;
  }
}
