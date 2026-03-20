import 'dart:isolate';

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/core/task_invocation.dart';
import 'package:stem/src/workflow/core/run_state.dart';
import 'package:stem/src/workflow/core/workflow_cancellation_policy.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_result.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:test/test.dart';

class _CapturingEnqueuer implements TaskEnqueuer {
  _CapturingEnqueuer(this._taskId);

  final String _taskId;
  Map<String, String>? lastHeaders;
  Map<String, Object?>? lastMeta;
  TaskEnqueueOptions? lastOptions;
  TaskCall<dynamic, dynamic>? lastCall;
  DateTime? lastNotBefore;

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    lastHeaders = headers;
    lastMeta = meta;
    lastOptions = enqueueOptions;
    lastNotBefore = notBefore;
    return _taskId;
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    lastCall = call;
    lastOptions = enqueueOptions;
    return _taskId;
  }
}

class _CapturingWorkflowCaller implements WorkflowCaller {
  String? lastWorkflowName;
  Map<String, Object?>? lastWorkflowParams;
  String? waitedRunId;

  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    lastWorkflowName = definition.name;
    lastWorkflowParams = definition.encodeParams(params);
    return 'run-1';
  }

  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) {
    return startWorkflowRef(
      call.definition,
      call.params,
      parentRunId: call.parentRunId,
      ttl: call.ttl,
      cancellationPolicy: call.cancellationPolicy,
    );
  }

  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) async {
    waitedRunId = runId;
    return WorkflowResult<TResult>(
      runId: runId,
      status: WorkflowStatus.completed,
      state: RunState(
        id: runId,
        workflow: definition.name,
        status: WorkflowStatus.completed,
        cursor: 0,
        params: const {},
        createdAt: DateTime.utc(2026),
        result: 'workflow-result',
      ),
      value: definition.decode('workflow-result'),
      rawResult: 'workflow-result',
    );
  }
}

class _CapturingWorkflowEventEmitter implements WorkflowEventEmitter {
  final List<String> topics = <String>[];
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<void> emitValue<T>(
    String topic,
    T value, {
    PayloadCodec<T>? codec,
  }) async {
    final encoded = codec != null ? codec.encode(value) : value;
    payloads.add(Map<String, Object?>.from(encoded! as Map));
    topics.add(topic);
  }

  @override
  Future<void> emitEvent<T>(WorkflowEventRef<T> event, T value) {
    return emitValue(event.topic, value, codec: event.codec);
  }
}

void main() {
  test('TaskInvocationContext.local merges headers/meta and lineage', () async {
    final enqueuer = _CapturingEnqueuer('task-1');
    final context = TaskInvocationContext.local(
      id: 'root-task',
      headers: const {'h1': 'v1'},
      meta: const {'m1': 'v1'},
      attempt: 2,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
      enqueuer: enqueuer,
    );

    await context.enqueue(
      'child',
      headers: const {'h2': 'v2'},
      meta: const {'m2': 'v2'},
    );

    expect(enqueuer.lastHeaders, containsPair('h1', 'v1'));
    expect(enqueuer.lastHeaders, containsPair('h2', 'v2'));
    expect(enqueuer.lastMeta, containsPair('m1', 'v1'));
    expect(enqueuer.lastMeta, containsPair('m2', 'v2'));
    expect(enqueuer.lastMeta, containsPair('stem.parentTaskId', 'root-task'));
    expect(enqueuer.lastMeta, containsPair('stem.parentAttempt', 2));
  });

  test('TaskInvocationContext.local forwards notBefore', () async {
    final enqueuer = _CapturingEnqueuer('task-1');
    final context = TaskInvocationContext.local(
      id: 'root-task',
      headers: const {},
      meta: const {},
      attempt: 0,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
      enqueuer: enqueuer,
    );
    final scheduledAt = DateTime.now().add(const Duration(minutes: 5));

    await context.enqueue('child', notBefore: scheduledAt);

    expect(enqueuer.lastNotBefore, scheduledAt);
  });

  test('TaskInvocationContext.local throws when enqueuer missing', () async {
    final context = TaskInvocationContext.local(
      id: 'no-enqueuer',
      headers: const {},
      meta: const {},
      attempt: 0,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
    );

    expect(
      () => context.enqueue('task'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => context.enqueueCall(
        const TaskDefinition<Map<String, Object?>, Object?>(
          name: 'demo',
          encodeArgs: _encodeArgs,
        ).call(const {'a': 1}),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'TaskInvocationContext.local enqueueCall merges call metadata',
    () async {
      final enqueuer = _CapturingEnqueuer('task-2');
      final context = TaskInvocationContext.local(
        id: 'root-task',
        headers: const {'h1': 'v1'},
        meta: const {'m1': 'v1'},
        attempt: 1,
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {Map<String, Object?>? data}) async {},
        enqueuer: enqueuer,
      );

      final definition = TaskDefinition<Map<String, Object?>, Object?>(
        name: 'demo.call',
        encodeArgs: (args) => args,
      );
      final call = definition.call(
        const {'value': 1},
        headers: const {'h2': 'v2'},
        meta: const {'m2': 'v2'},
      );

      await context.enqueueCall(call);

      final merged = enqueuer.lastCall;
      expect(merged, isNotNull);
      expect(merged!.headers['h1'], 'v1');
      expect(merged.headers['h2'], 'v2');
      expect(merged.meta['stem.parentTaskId'], 'root-task');
    },
  );

  test('TaskInvocationContext.local delegates typed workflow calls', () async {
    final workflows = _CapturingWorkflowCaller();
    final context = TaskInvocationContext.local(
      id: 'root-task',
      headers: const {},
      meta: const {},
      attempt: 1,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
      workflows: workflows,
    );
    final definition = WorkflowRef<Map<String, Object?>, String>(
      name: 'workflow.child',
      encodeParams: (params) => params,
    );

    final runId = await context.startWorkflowRef(
      definition,
      const {'value': 'child'},
    );
    final result = await context.waitForWorkflowRef(runId, definition);

    expect(runId, 'run-1');
    expect(workflows.lastWorkflowName, 'workflow.child');
    expect(workflows.lastWorkflowParams, {'value': 'child'});
    expect(workflows.waitedRunId, 'run-1');
    expect(result?.value, 'workflow-result');
  });

  test('TaskInvocationContext.local delegates typed workflow events', () async {
    final workflowEvents = _CapturingWorkflowEventEmitter();
    final context = TaskInvocationContext.local(
      id: 'root-task',
      headers: const {},
      meta: const {},
      attempt: 1,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
      workflowEvents: workflowEvents,
    );

    await context.emitValue('workflow.inline', const {'value': 'inline'});
    await context.emitEvent(_eventRef, const _WorkflowEventPayload('event'));

    expect(workflowEvents.topics, ['workflow.inline', 'workflow.ready']);
    expect(workflowEvents.payloads, [
      {'value': 'inline'},
      {'value': 'event'},
    ]);
  });

  test('TaskInvocationContext.remote sends control signals', () async {
    final control = ReceivePort();
    addTearDown(control.close);

    final signals = <TaskInvocationSignal>[];
    control.listen((message) {
      if (message is EnqueueTaskSignal) {
        signals.add(message);
        message.replyPort.send(const TaskEnqueueResponse(taskId: 'remote-id'));
      } else if (message is TaskInvocationSignal) {
        signals.add(message);
      }
    });

    final context = TaskInvocationContext.remote(
      id: 'remote-task',
      controlPort: control.sendPort,
      headers: const {},
      meta: const {},
      attempt: 0,
    );

    // Cascades can't be used here because the calls are awaited separately.
    // ignore: cascade_invocations
    context.heartbeat();
    await context.extendLease(const Duration(seconds: 1));
    await context.progress(25, data: const {'step': 1});

    final taskId = await context.enqueue('demo.remote');
    expect(taskId, 'remote-id');

    expect(signals.any((signal) => signal is HeartbeatSignal), isTrue);
    expect(signals.any((signal) => signal is ExtendLeaseSignal), isTrue);
    expect(signals.any((signal) => signal is ProgressSignal), isTrue);
    expect(signals.any((signal) => signal is EnqueueTaskSignal), isTrue);
  });

  test(
    'TaskInvocationContext.remote proxies workflow start and wait',
    () async {
      final control = ReceivePort();
      addTearDown(control.close);

      control.listen((message) {
        if (message is StartWorkflowSignal) {
          message.replyPort.send(
            const StartWorkflowResponse(runId: 'remote-run'),
          );
        } else if (message is WaitForWorkflowSignal) {
          message.replyPort.send(
            WaitForWorkflowResponse(
              result: WorkflowResult<Object?>(
                runId: message.request.runId,
                status: WorkflowStatus.completed,
                state: RunState(
                  id: message.request.runId,
                  workflow: message.request.workflowName,
                  status: WorkflowStatus.completed,
                  cursor: 0,
                  params: const {},
                  createdAt: DateTime.utc(2026),
                  result: 'workflow-result',
                ),
                value: 'workflow-result',
                rawResult: 'workflow-result',
              ).toJson(),
            ),
          );
        }
      });

      final context = TaskInvocationContext.remote(
        id: 'remote-task',
        controlPort: control.sendPort,
        headers: const {},
        meta: const {},
        attempt: 0,
      );
      final definition = WorkflowRef<Map<String, Object?>, String>(
        name: 'workflow.child',
        encodeParams: (params) => params,
      );

      final runId = await context.startWorkflowRef(
        definition,
        const {'value': 'child'},
      );
      final result = await context.waitForWorkflowRef(runId, definition);

      expect(runId, 'remote-run');
      expect(result?.value, 'workflow-result');
    },
  );

  test(
    'TaskInvocationContext.remote proxies workflow event emission',
    () async {
      final control = ReceivePort();
      addTearDown(control.close);

      EmitWorkflowEventRequest? request;
      control.listen((message) {
        if (message is EmitWorkflowEventSignal) {
          request = message.request;
          message.replyPort.send(const EmitWorkflowEventResponse());
        }
      });

      final context = TaskInvocationContext.remote(
        id: 'remote-task',
        controlPort: control.sendPort,
        headers: const {},
        meta: const {},
        attempt: 0,
      );

      await context.emitEvent(_eventRef, const _WorkflowEventPayload('remote'));

      expect(request?.topic, 'workflow.ready');
      expect(request?.payload, {'value': 'remote'});
    },
  );

  test('TaskInvocationContext.remote surfaces enqueue errors', () async {
    final control = ReceivePort();
    addTearDown(control.close);

    control.listen((message) {
      if (message is EnqueueTaskSignal) {
        message.replyPort.send(const TaskEnqueueResponse(error: 'nope'));
      }
    });

    final context = TaskInvocationContext.remote(
      id: 'remote-task',
      controlPort: control.sendPort,
      headers: const {},
      meta: const {},
      attempt: 0,
    );

    await expectLater(
      () => context.enqueue('demo.remote'),
      throwsA(isA<StateError>()),
    );
  });

  test('TaskInvocationContext.remote surfaces workflow errors', () async {
    final control = ReceivePort();
    addTearDown(control.close);

    control.listen((message) {
      if (message is StartWorkflowSignal) {
        message.replyPort.send(
          const StartWorkflowResponse(error: 'workflow nope'),
        );
      }
    });

    final context = TaskInvocationContext.remote(
      id: 'remote-task',
      controlPort: control.sendPort,
      headers: const {},
      meta: const {},
      attempt: 0,
    );
    final definition = WorkflowRef<Map<String, Object?>, String>(
      name: 'workflow.child',
      encodeParams: (params) => params,
    );

    await expectLater(
      () => context.startWorkflowRef(definition, const {'value': 'child'}),
      throwsA(isA<StateError>()),
    );
  });

  test('TaskInvocationContext.remote surfaces workflow event errors', () async {
    final control = ReceivePort();
    addTearDown(control.close);

    control.listen((message) {
      if (message is EmitWorkflowEventSignal) {
        message.replyPort.send(
          const EmitWorkflowEventResponse(error: 'event nope'),
        );
      }
    });

    final context = TaskInvocationContext.remote(
      id: 'remote-task',
      controlPort: control.sendPort,
      headers: const {},
      meta: const {},
      attempt: 0,
    );

    await expectLater(
      () => context.emitEvent(_eventRef, const _WorkflowEventPayload('oops')),
      throwsA(isA<StateError>()),
    );
  });

  test('TaskInvocationContext.retry throws TaskRetryRequest', () {
    final context = TaskInvocationContext.local(
      id: 'retry-task',
      headers: const {},
      meta: const {},
      attempt: 0,
      heartbeat: () {},
      extendLease: (_) async {},
      progress: (_, {Map<String, Object?>? data}) async {},
      enqueuer: _CapturingEnqueuer('noop'),
    );

    expect(
      () => context.retry(countdown: const Duration(seconds: 5)),
      throwsA(isA<TaskRetryRequest>()),
    );
  });
}

class _WorkflowEventPayload {
  const _WorkflowEventPayload(this.value);

  final String value;
}

const PayloadCodec<_WorkflowEventPayload> _eventPayloadCodec =
    PayloadCodec<_WorkflowEventPayload>(
      encode: _encodeWorkflowEventPayload,
      decode: _decodeWorkflowEventPayload,
    );

const WorkflowEventRef<_WorkflowEventPayload> _eventRef =
    WorkflowEventRef<_WorkflowEventPayload>(
      topic: 'workflow.ready',
      codec: _eventPayloadCodec,
    );

Map<String, Object?> _encodeWorkflowEventPayload(_WorkflowEventPayload value) {
  return {'value': value.value};
}

_WorkflowEventPayload _decodeWorkflowEventPayload(Object? payload) {
  return _WorkflowEventPayload(
    (payload! as Map<String, Object?>)['value']! as String,
  );
}

Map<String, Object?> _encodeArgs(Map<String, Object?> args) => args;
