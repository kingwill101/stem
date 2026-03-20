import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';
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

  test(
    'WorkflowScriptStepContext.enqueue delegates to the configured enqueuer',
    () async {
      final enqueuer = _RecordingTaskEnqueuer();
      final context = _FakeWorkflowScriptStepContext(enqueuer: enqueuer);

      final taskId = await context.enqueue(
        'tasks.child',
        args: const {'value': 42},
        meta: const {'source': 'script'},
      );

      expect(taskId, equals('recorded-1'));
      expect(enqueuer.lastName, equals('tasks.child'));
      expect(enqueuer.lastArgs, equals({'value': 42}));
      expect(enqueuer.lastMeta, containsPair('source', 'script'));
    },
  );

  test(
    'WorkflowScriptStepContext.enqueue throws when no enqueuer is configured',
    () {
      final context = _FakeWorkflowScriptStepContext();

      expect(() => context.enqueue('tasks.child'), throwsStateError);
    },
  );
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
  _FakeWorkflowScriptStepContext({
    Object? resumeData,
    TaskEnqueuer? enqueuer,
    WorkflowCaller? workflows,
  }) : _resumeData = resumeData,
       _enqueuer = enqueuer,
       _workflows = workflows;

  Object? _resumeData;
  final TaskEnqueuer? _enqueuer;
  final WorkflowCaller? _workflows;
  final List<String> awaitedTopics = <String>[];
  final List<Duration> sleepCalls = <Duration>[];

  @override
  TaskEnqueuer? get enqueuer => _enqueuer;

  @override
  WorkflowCaller? get workflows => _workflows;

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

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    Map<String, Object?> meta = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final delegate = _enqueuer;
    if (delegate == null) {
      throw StateError('WorkflowScriptStepContext has no enqueuer configured');
    }
    return delegate.enqueue(
      name,
      args: args,
      headers: headers,
      meta: meta,
      options: options,
      notBefore: notBefore,
      enqueueOptions: enqueueOptions,
    );
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    final delegate = _enqueuer;
    if (delegate == null) {
      throw StateError('WorkflowScriptStepContext has no enqueuer configured');
    }
    return delegate.enqueueCall(call, enqueueOptions: enqueueOptions);
  }

  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    final caller = _workflows;
    if (caller == null) {
      throw StateError(
        'WorkflowScriptStepContext has no workflow caller configured',
      );
    }
    return caller.startWorkflowRef(
      definition,
      params,
      parentRunId: parentRunId,
      ttl: ttl,
      cancellationPolicy: cancellationPolicy,
    );
  }

  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) async {
    final caller = _workflows;
    if (caller == null) {
      throw StateError(
        'WorkflowScriptStepContext has no workflow caller configured',
      );
    }
    return caller.startWorkflowCall(call);
  }

  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) async {
    final caller = _workflows;
    if (caller == null) {
      throw StateError(
        'WorkflowScriptStepContext has no workflow caller configured',
      );
    }
    return caller.waitForWorkflowRef(
      runId,
      definition,
      pollInterval: pollInterval,
      timeout: timeout,
    );
  }
}

class _RecordingTaskEnqueuer implements TaskEnqueuer {
  String? lastName;
  Map<String, Object?>? lastArgs;
  Map<String, Object?>? lastMeta;

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    Map<String, Object?> meta = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    lastName = name;
    lastArgs = Map<String, Object?>.from(args);
    lastMeta = Map<String, Object?>.from(meta);
    return 'recorded-1';
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueue(
      call.name,
      args: call.encodeArgs(),
      headers: call.headers,
      meta: call.meta,
      options: call.resolveOptions(),
      notBefore: call.notBefore,
      enqueueOptions: enqueueOptions ?? call.enqueueOptions,
    );
  }
}
