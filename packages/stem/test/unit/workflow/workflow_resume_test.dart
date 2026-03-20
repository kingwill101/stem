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

  test('FlowContext.sleepFor uses named args and throws suspension signal', () {
    final firstContext = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
    );

    expect(
      () => firstContext.sleepFor(duration: const Duration(seconds: 1)),
      throwsA(isA<WorkflowSuspensionSignal>()),
    );
    expect(firstContext.takeControl()?.type, FlowControlType.sleep);

    final resumedContext = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
      resumeData: true,
    );

    expect(
      resumedContext.sleepFor(duration: const Duration(seconds: 1)),
      completes,
    );
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
    'FlowContext.waitForEventRefValue uses named args and resumes with payload',
    () {
      const event = WorkflowEventRef<_ResumePayload>(
        topic: 'demo.event',
        codec: _resumePayloadCodec,
      );
      final waiting = FlowContext(
        workflow: 'demo',
        runId: 'run-1',
        stepName: 'wait',
        params: const {},
        previousResult: null,
        stepIndex: 0,
      );

      expect(
        () => waiting.waitForEventRefValue(event: event),
        throwsA(isA<WorkflowSuspensionSignal>()),
      );
      expect(waiting.takeControl()?.topic, 'demo.event');

      final resumed = FlowContext(
        workflow: 'demo',
        runId: 'run-1',
        stepName: 'wait',
        params: const {},
        previousResult: null,
        stepIndex: 0,
        resumeData: const {'message': 'approved'},
      );

      expect(
        resumed.waitForEventRefValue(event: event),
        completion(
          isA<_ResumePayload>().having(
            (value) => value.message,
            'message',
            'approved',
          ),
        ),
      );
    },
  );

  test('FlowContext.waitForEvent uses named args and resumes with payload', () {
    final waiting = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
    );

    expect(
      () => waiting.waitForEvent<_ResumePayload>(
        topic: 'demo.event',
        codec: _resumePayloadCodec,
      ),
      throwsA(isA<WorkflowSuspensionSignal>()),
    );
    expect(waiting.takeControl()?.topic, 'demo.event');

    final resumed = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
      resumeData: const {'message': 'approved'},
    );

    expect(
      resumed.waitForEvent<_ResumePayload>(
        topic: 'demo.event',
        codec: _resumePayloadCodec,
      ),
      completion(
        isA<_ResumePayload>().having(
          (value) => value.message,
          'message',
          'approved',
        ),
      ),
    );
  });

  test('FlowContext.awaitEventRef reuses the event topic', () {
    const event = WorkflowEventRef<_ResumePayload>(
      topic: 'demo.event',
      codec: _resumePayloadCodec,
    );
    final deadline = DateTime.parse('2026-01-01T00:00:00Z');
    final context = FlowContext(
      workflow: 'demo',
      runId: 'run-1',
      stepName: 'wait',
      params: const {},
      previousResult: null,
      stepIndex: 0,
    );

    final control = context.awaitEventRef(
      event,
      deadline: deadline,
      data: const {'source': 'flow'},
    );

    expect(control.type, FlowControlType.waitForEvent);
    expect(control.topic, 'demo.event');
    expect(control.deadline, deadline);
    expect(control.data, containsPair('source', 'flow'));
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

  test(
    'WorkflowScriptStepContext expression helpers use named args and '
    'throw suspension signal',
    () {
      final sleeping = _FakeWorkflowScriptStepContext();
      expect(
        sleeping.sleepFor(duration: const Duration(milliseconds: 10)),
        throwsA(isA<WorkflowSuspensionSignal>()),
      );
      expect(sleeping.sleepCalls, [const Duration(milliseconds: 10)]);

      final resumedSleep = _FakeWorkflowScriptStepContext(resumeData: true);
      expect(
        resumedSleep.sleepFor(duration: const Duration(milliseconds: 10)),
        completes,
      );
      expect(resumedSleep.sleepCalls, isEmpty);

      final waiting = _FakeWorkflowScriptStepContext();
      expect(
        waiting.waitForEvent<_ResumePayload>(
          topic: 'demo.event',
          codec: _resumePayloadCodec,
        ),
        throwsA(isA<WorkflowSuspensionSignal>()),
      );
      expect(waiting.awaitedTopics, ['demo.event']);

      final resumedEvent = _FakeWorkflowScriptStepContext(
        resumeData: const {'message': 'approved'},
      );
      expect(
        resumedEvent.waitForEvent<_ResumePayload>(
          topic: 'demo.event',
          codec: _resumePayloadCodec,
        ),
        completion(
          isA<_ResumePayload>().having(
            (value) => value.message,
            'message',
            'approved',
          ),
        ),
      );
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
    'WorkflowScriptStepContext.waitForEventRefValue uses named args and '
    'resumes with payload',
    () {
      const event = WorkflowEventRef<_ResumePayload>(
        topic: 'demo.event',
        codec: _resumePayloadCodec,
      );
      final waiting = _FakeWorkflowScriptStepContext();

      expect(
        waiting.waitForEventRefValue(event: event),
        throwsA(isA<WorkflowSuspensionSignal>()),
      );
      expect(waiting.awaitedTopics, ['demo.event']);

      final resumed = _FakeWorkflowScriptStepContext(
        resumeData: const {'message': 'approved'},
      );
      expect(
        resumed.waitForEventRefValue(event: event),
        completion(
          isA<_ResumePayload>().having(
            (value) => value.message,
            'message',
            'approved',
          ),
        ),
      );
    },
  );

  test(
    'WorkflowEventRef.waitValueWith delegates to both flow and script '
    'contexts',
    () {
      const event = WorkflowEventRef<_ResumePayload>(
        topic: 'demo.event',
        codec: _resumePayloadCodec,
      );

      final flowWaiting = FlowContext(
        workflow: 'demo',
        runId: 'run-1',
        stepName: 'wait',
        params: const {},
        previousResult: null,
        stepIndex: 0,
      );
      expect(event.waitValueWith(flowWaiting), isNull);
      expect(flowWaiting.takeControl()?.topic, 'demo.event');

      final flowResumed = FlowContext(
        workflow: 'demo',
        runId: 'run-1',
        stepName: 'wait',
        params: const {},
        previousResult: null,
        stepIndex: 0,
        resumeData: const {'message': 'approved'},
      );
      expect(event.waitValueWith(flowResumed)?.message, 'approved');

      final scriptWaiting = _FakeWorkflowScriptStepContext();
      expect(event.waitValueWith(scriptWaiting), isNull);
      expect(scriptWaiting.awaitedTopics, ['demo.event']);
    },
  );

  test(
    'WorkflowEventRef.waitWith delegates to both flow and script contexts',
    () {
      const event = WorkflowEventRef<_ResumePayload>(
        topic: 'demo.event',
        codec: _resumePayloadCodec,
      );

      final flowWaiting = FlowContext(
        workflow: 'demo',
        runId: 'run-1',
        stepName: 'wait',
        params: const {},
        previousResult: null,
        stepIndex: 0,
      );
      expect(
        () => event.waitWith(flowWaiting),
        throwsA(isA<WorkflowSuspensionSignal>()),
      );
      expect(flowWaiting.takeControl()?.topic, 'demo.event');

      final scriptResumed = _FakeWorkflowScriptStepContext(
        resumeData: const {'message': 'approved'},
      );
      expect(
        event.waitWith(scriptResumed),
        completion(
          isA<_ResumePayload>().having(
            (value) => value.message,
            'message',
            'approved',
          ),
        ),
      );
    },
  );

  test('WorkflowEventRef wait helpers reject unsupported waiter types', () {
    const event = WorkflowEventRef<_ResumePayload>(
      topic: 'demo.event',
      codec: _resumePayloadCodec,
    );

    expect(
      () => event.waitValueWith('invalid'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => event.waitWith('invalid'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'WorkflowScriptStepContext.awaitEventRef reuses the event topic',
    () async {
      const event = WorkflowEventRef<_ResumePayload>(
        topic: 'demo.event',
        codec: _resumePayloadCodec,
      );
      final deadline = DateTime.parse('2026-01-01T00:00:00Z');
      final context = _FakeWorkflowScriptStepContext();

      await context.awaitEventRef(
        event,
        deadline: deadline,
        data: const {'source': 'script'},
      );

      expect(context.awaitedTopics, ['demo.event']);
      expect(context.awaitedDeadline, deadline);
      expect(context.awaitedData, containsPair('source', 'script'));
    },
  );

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
  DateTime? awaitedDeadline;
  Map<String, Object?>? awaitedData;
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
    awaitedDeadline = deadline;
    awaitedData = data == null ? null : Map<String, Object?>.from(data);
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
